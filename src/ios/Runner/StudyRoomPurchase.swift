import Flutter
import StoreKit

/// One non-consumable product; the same implementation serves Xcode and the App Store.
@MainActor
final class StudyRoomPurchase {
  static let productID = "vip.ichiki.javalee.yzc.studyroom.lifetime"

  private let channel: FlutterMethodChannel
  private var product: Product?
  private var unlocked = false
  private var message: String?
  private var revision = 0
  private var entitlementTask: Task<Void, Never>?
  private var operationInProgress = false
  private var updatesTask: Task<Void, Never>?
  private var unfinishedTask: Task<Void, Never>?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "yuzhichu/study_room_purchase", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor [weak self] in
        guard let self = self else {
          result(FlutterError(code: "unavailable", message: "unavailable", details: nil))
          return
        }
        await self.handle(call, result: result)
      }
    }
    // Start listening before product requests or purchases, including approval on another device.
    updatesTask = Task { [weak self] in
      for await value in StoreKit.Transaction.updates {
        if Task.isCancelled { return }
        await self?.receive(value)
      }
    }
    unfinishedTask = Task { [weak self] in
      for await value in StoreKit.Transaction.unfinished {
        if Task.isCancelled { return }
        await self?.receive(value)
      }
    }
  }

  private func snapshot() -> [String: Any] {
    var state: [String: Any] = [
      "revision": revision,
      "unlocked": unlocked,
      "canPay": AppStore.canMakePayments,
    ]
    if let product = product { state["price"] = product.displayPrice }
    if let message = message { state["messageCode"] = message }
    return state
  }

  private func publish() {
    revision += 1
    channel.invokeMethod("state", arguments: snapshot())
  }

  private func refreshEntitlements() async {
    // Serialize reads: an older snapshot cannot overwrite a purchase/refund update,
    // and every caller waits until its entitlement result has been published.
    let previous = entitlementTask
    let task = Task { [weak self] in
      await previous?.value
      guard let self = self else { return }
      await self.readEntitlements()
    }
    entitlementTask = task
    await task.value
  }

  private func readEntitlements() async {
    var entitled = false
    var verificationFailed = false
    for await value in StoreKit.Transaction.currentEntitlements {
      switch value {
      case .verified(let transaction):
        if transaction.productID == Self.productID,
           transaction.productType == .nonConsumable,
           transaction.revocationDate == nil, !transaction.isUpgraded {
          entitled = true
        }
      case .unverified(let transaction, _):
        if transaction.productID == Self.productID { verificationFailed = true }
      }
    }
    unlocked = entitled
    if verificationFailed && !entitled {
      message = "verification"
    }
    publish()
  }

  private func receive(_ value: VerificationResult<StoreKit.Transaction>) async {
    switch value {
    case .verified(let transaction):
      guard transaction.productID == Self.productID,
            transaction.productType == .nonConsumable else { return }
      message = nil
      await refreshEntitlements()
      // Entitlements are published before acknowledging delivery to StoreKit.
      if unlocked || transaction.revocationDate != nil {
        await transaction.finish()
      } else {
        // Leave undelivered purchases unfinished so StoreKit can redeliver them.
        if message == nil { message = "sync_pending" }
        publish()
      }
    case .unverified(let transaction, _):
      guard transaction.productID == Self.productID else { return }
      await refreshEntitlements()
      message = "verification"
      publish()
      // Do not grant access or finish a transaction that failed verification.
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) async {
    switch call.method {
    case "refresh":
      await refreshEntitlements()
      result(snapshot())
    case "loadProduct":
      do {
        let products = try await Product.products(for: [Self.productID])
        product = products.first { $0.id == Self.productID && $0.type == .nonConsumable }
        if product == nil {
          message = "product_unavailable"
        } else if !AppStore.canMakePayments {
          message = "restricted"
        } else {
          message = nil
        }
        publish()
        result(snapshot())
      } catch {
        product = nil
        message = "product"
        publish()
        result(FlutterError(code: "product", message: message, details: String(describing: error)))
      }
    case "purchase", "restore":
      guard !operationInProgress else {
        result(FlutterError(code: "busy", message: "busy", details: nil))
        return
      }
      operationInProgress = true
      defer { operationInProgress = false }
      message = nil
      do {
        if call.method == "restore" {
          // Explicit user action only: sync may ask the user to sign in.
          try await AppStore.sync()
          await refreshEntitlements()
          if !unlocked && message == nil { message = "restore_empty" }
        } else {
          guard AppStore.canMakePayments else {
            result(FlutterError(code: "restricted", message: "restricted", details: nil))
            return
          }
          guard let product = product else {
            result(FlutterError(code: "product_unavailable", message: "product_unavailable", details: nil))
            return
          }
          await refreshEntitlements()
          if !unlocked {
            switch try await product.purchase() {
            case .success(let value):
              switch value {
              case .verified(let transaction):
                guard transaction.productID == Self.productID,
                      transaction.productType == .nonConsumable else {
                  result(FlutterError(code: "product_mismatch", message: "product_mismatch", details: nil))
                  return
                }
                await receive(value)
              case .unverified:
                await receive(value)
                result(FlutterError(code: "verification", message: "verification", details: nil))
                return
              }
            case .pending:
              message = "pending"
            case .userCancelled:
              message = "cancelled"
            @unknown default:
              message = "incomplete"
            }
          }
        }
        publish()
        result(snapshot())
      } catch {
        // Refresh without sync so a failed request cannot erase valid offline ownership.
        await refreshEntitlements()
        message = call.method == "restore" ? "restore" : "purchase"
        publish()
        result(FlutterError(code: call.method, message: message, details: String(describing: error)))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  deinit {
    updatesTask?.cancel()
    unfinishedTask?.cancel()
  }
}
