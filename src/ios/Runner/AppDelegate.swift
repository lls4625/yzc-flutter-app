import Flutter
import UIKit
import AVFoundation
import MediaPlayer
import Network
import NaturalLanguage

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // TODO: Replace this development placeholder with the App Store numeric app ID before release.
  private static let appStoreAppID = "0000000000"
  private var lessonPlayback: LessonPlayback?
  private var courseVideo: CourseVideoPlayback?
  private var practiceSpeech: PracticeSpeech?
  private var studyRoomPurchase: StudyRoomPurchase?
  private var developerTipPurchase: DeveloperTipPurchase?
  private var deviceChannel: FlutterMethodChannel?
  private var dictationTokenizerChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    studyRoomPurchase = StudyRoomPurchase(messenger: engineBridge.applicationRegistrar.messenger())
    developerTipPurchase = DeveloperTipPurchase(messenger: engineBridge.applicationRegistrar.messenger())
    lessonPlayback = LessonPlayback(messenger: engineBridge.applicationRegistrar.messenger())
    practiceSpeech = PracticeSpeech(messenger: engineBridge.applicationRegistrar.messenger())
    let video = CourseVideoPlayback(messenger: engineBridge.applicationRegistrar.messenger())
    courseVideo = video
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CourseVideo") {
      registrar.register(CourseVideoViewFactory(video), withId: "yuzhichu/course_video_surface")
    }
    video.beforePlay = { [weak self] in
      self?.lessonPlayback?.stopForVideo()
      self?.practiceSpeech?.stopForVideo()
    }
    lessonPlayback?.beforeAudioStart = { [weak video] in video?.stop() }
    lessonPlayback?.onBookBlocked = { [weak video] book in video?.blockBook(book) }
    lessonPlayback?.onBookUnblocked = { [weak video] book in video?.unblockBook(book) }
    dictationTokenizerChannel = FlutterMethodChannel(name: "yuzhichu/dictation_tokenizer", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    dictationTokenizerChannel?.setMethodCallHandler { call, result in
      guard call.method == "tokenize" else { result(FlutterMethodNotImplemented); return }
      guard let text = call.arguments as? String else {
        result(FlutterError(code: "text", message: "日文原文无效", details: nil)); return
      }
      let tokenizer = NLTokenizer(unit: .word)
      tokenizer.setLanguage(.japanese)
      tokenizer.string = text
      var parts: [String] = []
      var cursor = text.startIndex
      tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
        if cursor < range.lowerBound { parts.append(String(text[cursor..<range.lowerBound])) }
        parts.append(String(text[range]))
        cursor = range.upperBound
        return true
      }
      if cursor < text.endIndex { parts.append(String(text[cursor..<text.endIndex])) }
      result(parts)
    }
    deviceChannel = FlutterMethodChannel(name: "yuzhichu/device", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    deviceChannel?.setMethodCallHandler { [weak self] call, result in
      if call.method == "info" {
        let device = UIDevice.current
        result(["device_type": device.userInterfaceIdiom == .pad ? "tablet" : "phone",
                "device_model": device.model, "os_name": device.systemName, "os_ver": device.systemVersion,
                "app_ver": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "app_build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""])
      } else if call.method == "freeSpace" {
        do {
          let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
          result(attributes[.systemFreeSize] as? NSNumber)
        } catch { result(FlutterError(code: "storage", message: "无法读取可用空间", details: nil)) }
      } else if call.method == "excludeDownloadedResourcesFromBackup" {
        do {
          let support = try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false)
          let root = support.appendingPathComponent("v3.1", isDirectory: true)
          // Only reproducible files. Never exclude the database, IDs or study receipt.
          for path in ["resources", "staging", "backups", "study/resources", "study/staging"] {
            var url = root.appendingPathComponent(path, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
              var values = URLResourceValues()
              values.isExcludedFromBackup = true
              try url.setResourceValues(values)
            }
          }
          result(nil)
        } catch {
          result(FlutterError(code: "backup_policy", message: "无法设置下载资源的备份属性", details: nil))
        }
      } else if call.method == "networkStatus" {
        guard let self = self else {
          result(FlutterError(code: "network", message: "无法读取网络状态", details: nil))
          return
        }
        self.readNetworkStatus(result)
      } else if call.method == "openSettings" {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      } else if call.method == "openAppReviewPage" {
        guard let url = URL(string: "https://apps.apple.com/app/id\(Self.appStoreAppID)?action=write-review") else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
      } else { result(FlutterMethodNotImplemented) }
    }
  }

  private func readNetworkStatus(_ result: @escaping FlutterResult) {
    let monitor = NWPathMonitor()
    var completed = false
    func finish(_ value: [String: String]) {
      guard !completed else { return }
      completed = true
      monitor.pathUpdateHandler = nil
      monitor.cancel()
      result(value)
    }
    monitor.pathUpdateHandler = { path in
      var reason = "unknown"
      if path.status == .unsatisfied {
        switch path.unsatisfiedReason {
        case .cellularDenied: reason = "cellularDenied"
        case .wifiDenied: reason = "wifiDenied"
        case .localNetworkDenied: reason = "localNetworkDenied"
        case .notAvailable: reason = "notAvailable"
        @unknown default: break
        }
      }
      let connection = path.usesInterfaceType(.wifi) ? "wifi" :
        (path.usesInterfaceType(.cellular) ? "cellular" : "other")
      finish(["status": path.status == .satisfied ? "available" : "unavailable",
              "reason": reason, "connection": connection])
    }
    monitor.start(queue: .main)
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
      finish(["status": "unknown", "reason": "unknown", "connection": "unknown"])
    }
  }
}

/// Receives only the highlighted material, never the complete question.
private final class PracticeSpeech: NSObject, AVSpeechSynthesizerDelegate {
  func stopForVideo() { stop() }
  private let channel: FlutterMethodChannel
  private var synthesizer: AVSpeechSynthesizer?
  private var lastUtterance: AVSpeechUtterance?
  private var requestID: String?
  private var completion: FlutterResult?
  private var observers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "yuzhichu/practice_speech", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "stop":
        if let id = args?["id"] as? String, id == self.requestID { self.stop() }
        result(nil)
      case "speak":
        guard let id = args?["id"] as? String,
              let segments = args?["segments"] as? [String], !segments.isEmpty else {
          result(FlutterError(code: "speech_text", message: "没有可朗读的正文", details: nil))
          return
        }
        self.speak(id: id, segments: segments, result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }
    observers.append(NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.stop() })
    observers.append(NotificationCenter.default.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { [weak self] note in
      if let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
         type == AVAudioSession.InterruptionType.began.rawValue { self?.stop() }
    })
    observers.append(NotificationCenter.default.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { [weak self] note in
      if let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
         reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.stop() }
    })
  }

  private func speak(id: String, segments: [String], result: @escaping FlutterResult) {
    stop()
    guard let voice = AVSpeechSynthesisVoice(language: "ja-JP") else {
      result(FlutterError(code: "speech_voice", message: "手机暂无可用的日语语音，请在系统设置中下载日语声音后重试。", details: nil))
      return
    }
    var utterances: [AVSpeechUtterance] = []
    var pause: TimeInterval = 0
    for (index, segment) in segments.enumerated() {
      if index > 0 { pause += 0.65 }
      let text = segment.trimmingCharacters(in: .whitespacesAndNewlines)
      // A blank at the end may leave only punctuation. Do not speak its name.
      if text.rangeOfCharacter(from: .alphanumerics) == nil { continue }
      let utterance = AVSpeechUtterance(string: text)
      utterance.voice = voice
      utterance.rate = AVSpeechUtteranceDefaultSpeechRate
      utterance.preUtteranceDelay = pause
      pause = 0
      utterances.append(utterance)
    }
    guard let last = utterances.last else {
      result(FlutterError(code: "speech_text", message: "没有可朗读的正文", details: nil))
      return
    }
    last.postUtteranceDelay = pause
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, options: [])
      try session.setActive(true)
    } catch {
      result(FlutterError(code: "speech_audio", message: "无法启动语音播放，请稍后重试。", details: nil))
      return
    }
    let speaker = AVSpeechSynthesizer()
    speaker.delegate = self
    synthesizer = speaker
    lastUtterance = last
    requestID = id
    completion = result
    for utterance in utterances { speaker.speak(utterance) }
  }

  private func stop() {
    let speaker = synthesizer
    speaker?.delegate = nil
    speaker?.stopSpeaking(at: .immediate)
    finish()
  }

  private func finish() {
    let result = completion
    let hadSpeech = synthesizer != nil
    completion = nil
    requestID = nil
    lastUtterance = nil
    synthesizer = nil
    if hadSpeech {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    result?(nil)
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    guard synthesizer === self.synthesizer, utterance === lastUtterance else { return }
    finish()
  }

  func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    guard synthesizer === self.synthesizer else { return }
    stop()
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }
}

// Course feature video transport. No demo queues or data enter this player.
private final class CourseVideoPlayback {
  let player = AVPlayer()
  var beforePlay: (() -> Void)?
  private let channel: FlutterMethodChannel
  private var owner = "", rowID = "", book = ""
  private var status = "idle", errorMessage: String?
  private var wantsPlayback = false
  private var speedSteps = 20, revision = 0, generation = 0, seekRevision = 0
  private var blockedBooks = Set<String>()
  private var itemObservation: NSKeyValueObservation?
  private var playbackObservation: NSKeyValueObservation?
  private var timeObserver: Any?
  private var loadTimeout: Timer?
  private var observers: [NSObjectProtocol] = []
  private let surfaces = NSHashTable<CourseVideoLayerView>.weakObjects()

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "yuzhichu/course_video", binaryMessenger: messenger)
    player.actionAtItemEnd = .pause
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, let args = call.arguments as? [String: Any],
            let incomingOwner = args["owner"] as? String else { result(nil); return }
      do {
        if call.method == "load" {
          try self.load(args, owner: incomingOwner)
        } else {
          // Late disposal of another course must never stop the new course.
          guard incomingOwner == self.owner else { result(nil); return }
          switch call.method {
          case "pause": self.pause()
          case "resume": try self.resume()
          case "stop": self.stop()
          case "speed":
            self.speedSteps = min(60, max(10, args["speedSteps"] as? Int ?? 20))
            if self.wantsPlayback && self.status == "ready" {
              self.player.rate = Float(self.speedSteps) / 20
            }
            self.publish()
          case "seek":
            if let seconds = args["seconds"] as? NSNumber { self.seek(seconds.doubleValue) }
          default: result(FlutterMethodNotImplemented); return
          }
        }
        result(self.snapshot())
      } catch {
        if call.method == "load", incomingOwner == self.owner { self.fail(error.localizedDescription) }
        result(FlutterError(code: "course_video", message: error.localizedDescription, details: nil))
      }
    }
    playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async { self?.publish() }
    }
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] _ in
      guard let self = self, self.status != "idle" else { return }
      self.publish()
    }
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
      guard let self = self, let item = note.object as? AVPlayerItem,
            item === self.player.currentItem else { return }
      self.wantsPlayback = false
      self.player.pause()
      self.status = "ended"
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
      self.publish()
    })
    observers.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
      guard let self = self, let item = note.object as? AVPlayerItem,
            item === self.player.currentItem else { return }
      self.fail("视频播放失败，请重新打开")
    })
    for name in [UIApplication.didEnterBackgroundNotification, UIApplication.willResignActiveNotification] {
      observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.pause() })
    }
    observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
      if let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
         value == AVAudioSession.InterruptionType.began.rawValue { self?.pause() }
    })
    observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
      if let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
         value == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.pause() }
    })
    observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
      self?.fail("系统媒体服务已重置，请重新打开视频")
    })
  }

  private func load(_ args: [String: Any], owner: String) throws {
    guard let path = args["path"] as? String, let id = args["id"] as? String,
          let book = args["book"] as? String, !blockedBooks.contains(book) else {
      throw videoError("教材正在更新，暂时无法播放")
    }
    let support = try FileManager.default.url(for: .applicationSupportDirectory,
      in: .userDomainMask, appropriateFor: nil, create: false)
    let root = support.appendingPathComponent("v3.1/resources").resolvingSymlinksInPath().standardizedFileURL
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    guard url.path.hasPrefix(root.path + "/"), url.deletingLastPathComponent().lastPathComponent == "mp3",
          url.pathExtension.lowercased() == "mp4", FileManager.default.fileExists(atPath: url.path) else {
      throw videoError("视频文件缺失或路径无效，请重新下载教材")
    }
    stop()
    self.owner = owner; rowID = id; self.book = book
    speedSteps = min(60, max(10, args["speedSteps"] as? Int ?? 20))
    status = "loading"; errorMessage = nil
    beforePlay?()
    try activateSession()
    wantsPlayback = UIApplication.shared.applicationState == .active
    let item = AVPlayerItem(url: url)
    item.audioTimePitchAlgorithm = .spectral
    player.replaceCurrentItem(with: item)
    refreshSurfaces()
    let current = generation
    loadTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
      guard let self = self, current == self.generation, self.status == "loading" else { return }
      self.fail("视频准备超时，请重试")
    }
    itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self = self, current == self.generation,
              item === self.player.currentItem, self.status != "error" else { return }
        if item.status == .readyToPlay {
          self.loadTimeout?.invalidate(); self.loadTimeout = nil
          self.status = "ready"
          if self.wantsPlayback { self.player.playImmediately(atRate: Float(self.speedSteps) / 20) }
          self.publish()
        } else if item.status == .failed {
          self.fail("视频格式无法播放或文件已损坏，请重新下载教材")
        }
      }
    }
    publish()
  }

  private func activateSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .moviePlayback, options: [])
    try session.setActive(true)
  }
  private func pause() {
    guard status != "idle" else { return }
    wantsPlayback = false
    player.pause()
    publish()
  }
  private func resume() throws {
    guard player.currentItem != nil, !blockedBooks.contains(book), status != "error",
          UIApplication.shared.applicationState == .active else { return }
    beforePlay?()
    try activateSession()
    wantsPlayback = true
    if status == "ended" {
      status = "ready"
      seek(0)
    } else if status == "ready" { player.playImmediately(atRate: Float(speedSteps) / 20) }
    publish()
  }
  private func seek(_ seconds: Double) {
    guard seconds.isFinite, status == "ready" || status == "ended" else { return }
    let duration = player.currentItem?.duration.seconds ?? 0
    guard duration.isFinite, duration > 0 else { return }
    seekRevision += 1
    let currentSeek = seekRevision, current = generation
    status = "ready"
    player.pause()
    player.seek(to: CMTime(seconds: min(duration, max(0, seconds)), preferredTimescale: 600),
      toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
      DispatchQueue.main.async {
        guard let self = self, finished, current == self.generation, currentSeek == self.seekRevision else { return }
        if self.wantsPlayback { self.player.playImmediately(atRate: Float(self.speedSteps) / 20) }
        self.publish()
      }
    }
  }
  func stop() {
    let hadItem = player.currentItem != nil
    generation += 1; seekRevision += 1
    wantsPlayback = false
    player.pause()
    loadTimeout?.invalidate(); loadTimeout = nil
    itemObservation = nil
    player.currentItem?.cancelPendingSeeks()
    player.replaceCurrentItem(with: nil)
    status = "idle"; rowID = ""; errorMessage = nil
    if hadItem { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    publish()
  }
  func blockBook(_ book: String) {
    blockedBooks.insert(book)
    if self.book == book { stop() }
  }
  func unblockBook(_ book: String) { blockedBooks.remove(book) }
  private func fail(_ message: String) {
    guard status != "idle" else { return }
    loadTimeout?.invalidate(); loadTimeout = nil
    wantsPlayback = false; player.pause()
    errorMessage = message; status = "error"
    publish()
  }
  private func snapshot() -> [String: Any] {
    let rawDuration = player.currentItem?.duration.seconds ?? 0
    let rawPosition = player.currentTime().seconds
    let size = player.currentItem?.presentationSize ?? .zero
    var state: [String: Any] = ["owner": owner, "revision": revision, "status": status,
      "playing": wantsPlayback, "speedSteps": speedSteps,
      "position": rawPosition.isFinite ? max(0, rawPosition) : 0,
      "duration": rawDuration.isFinite ? max(0, rawDuration) : 0,
      "aspectRatio": size.width > 0 && size.height > 0 ? size.width / size.height : 16.0 / 9.0]
    if !rowID.isEmpty { state["id"] = rowID }
    if let error = errorMessage { state["error"] = error }
    return state
  }
  private func publish() {
    revision += 1
    if !owner.isEmpty { channel.invokeMethod("state", arguments: snapshot()) }
  }
  private func videoError(_ message: String) -> NSError {
    NSError(domain: "CourseVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }
  func attach(_ surface: CourseVideoLayerView) {
    surfaces.add(surface)
    surface.onWindowChanged = { [weak self] in self?.refreshSurfaces() }
    refreshSurfaces()
  }
  func detach(_ surface: CourseVideoLayerView) {
    surface.videoLayer.player = nil
    surfaces.remove(surface)
    refreshSurfaces()
  }
  private func refreshSurfaces() {
    let available = surfaces.allObjects.filter { $0.owner == owner && $0.window != nil }
    let selected = available.first(where: { $0.fullscreen }) ?? available.first
    for surface in surfaces.allObjects { surface.videoLayer.player = surface === selected ? player : nil }
  }
  deinit {
    loadTimeout?.invalidate()
    if let observer = timeObserver { player.removeTimeObserver(observer) }
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }
}

private final class CourseVideoLayerView: UIView {
  let owner: String
  let fullscreen: Bool
  var onWindowChanged: (() -> Void)?
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer }
  init(frame: CGRect, owner: String, fullscreen: Bool) {
    self.owner = owner; self.fullscreen = fullscreen
    super.init(frame: frame)
    backgroundColor = .black
    isUserInteractionEnabled = false
    videoLayer.videoGravity = .resizeAspect
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
  override func didMoveToWindow() { super.didMoveToWindow(); onWindowChanged?() }
}

private final class CourseVideoNativeView: NSObject, FlutterPlatformView {
  private let surface: CourseVideoLayerView
  private let playback: CourseVideoPlayback
  init(frame: CGRect, args: [String: Any], playback: CourseVideoPlayback) {
    self.playback = playback
    surface = CourseVideoLayerView(frame: frame, owner: args["owner"] as? String ?? "",
      fullscreen: args["fullscreen"] as? Bool ?? false)
    super.init()
    playback.attach(surface)
  }
  func view() -> UIView { surface }
  deinit { playback.detach(surface) }
}

private final class CourseVideoViewFactory: NSObject, FlutterPlatformViewFactory {
  private let playback: CourseVideoPlayback
  init(_ playback: CourseVideoPlayback) { self.playback = playback; super.init() }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    CourseVideoNativeView(frame: frame, args: args as? [String: Any] ?? [:], playback: playback)
  }
}

/// App-owned playback: Flutter pages only submit queues and observe state.
private final class LessonPlayback {
  var beforeAudioStart: (() -> Void)?
  var onBookBlocked: ((String) -> Void)?
  var onBookUnblocked: ((String) -> Void)?
  func stopForVideo() {
    commandRevision += 1 // Invalidate delayed audio starts as well as the queue.
    player.volume = 1
    stop()
  }
  private struct Clip {
    let id: String
    let path: String
  }

  private final class PreparedClip {
    let index: Int
    let asset: AVURLAsset
    var item: AVPlayerItem?
    var error: String?

    init(index: Int, path: String) {
      self.index = index
      asset = AVURLAsset(url: URL(fileURLWithPath: path), options: [
        AVURLAssetPreferPreciseDurationAndTimingKey: true
      ])
    }
  }

  private let channel: FlutterMethodChannel
  private var player = AVPlayer()
  private var clips: [Clip] = []
  private var lesson = "", title = ""
  private var albumTitle = ""
  private var commandRevision = 0
  private var blockedBooks = Set<String>()
  private var words = true, batch = false, wantsPlayback = false, interrupted = false
  private var index = 0, repetition = 0, repeatCount = 1, intervalSteps = 0
  private var speed: Float = 1
  private var generation = 0
  private var revision = 0
  private var preparing = false
  private var currentClip: PreparedClip?
  private var nextClip: PreparedClip?
  private var gapRemaining: TimeInterval?
  private var gapDeadline: Date?
  private var gapTimer: Timer?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var itemObservation: NSKeyValueObservation?
  private var playbackObservation: NSKeyValueObservation?
  private var timeObserver: Any?
  private var observers: [NSObjectProtocol] = []
  private var errorMessage: String?
  private var completedClipId: String?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "yuzhichu/lesson_playback", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      do {
        switch call.method {
        case "state": break
        case "blockBook":
          if let args = call.arguments as? [String: Any], let book = args["book"] as? String {
            self.blockedBooks.insert(book)
            self.onBookBlocked?(book)
            if self.lesson.hasPrefix(book + ":") {
              self.smoothCommand(FlutterMethodCall(methodName: "stop", arguments: nil), result: result)
              return
            }
          }
        case "unblockBook":
          if let args = call.arguments as? [String: Any], let book = args["book"] as? String {
            self.blockedBooks.remove(book)
            self.onBookUnblocked?(book)
          }
        case "start", "stop":
          self.smoothCommand(call, result: result)
          return
        case "resume": try self.resume()
        case "configure":
          let args = call.arguments as? [String: Any] ?? [:]
          if let value = args["speed"] as? NSNumber {
            self.speed = min(3, max(0.5, value.floatValue))
            if self.wantsPlayback && !self.interrupted && !self.preparing && self.gapRemaining == nil {
              self.player.rate = self.speed
            }
          }
          if let value = args["repeat"] as? Int {
            self.repeatCount = min(5, max(1, value))
            self.preloadNextClip()
          }
          if let value = args["intervalSteps"] as? Int { self.intervalSteps = min(10, max(0, value)) }
          self.publish()
        default: result(FlutterMethodNotImplemented); return
        }
        result(self.snapshot())
      } catch {
        result(FlutterError(code: "lesson_audio", message: error.localizedDescription, details: nil))
      }
    }
    observePlayer()
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
      guard let self = self, let item = note.object as? AVPlayerItem,
            item === self.player.currentItem else { return }
      self.finishClip()
    })
    observers.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil, queue: .main) { [weak self] note in
      guard let self = self, let item = note.object as? AVPlayerItem,
            item === self.player.currentItem else { return }
      self.fail("音频播放失败，请重新开始")
    })
    observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
      self?.handleInterruption(note)
    })
    observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
      if let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
         reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
        self?.pause()
      }
    })
    observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
      guard let self = self else { return }
      self.stop()
      self.playbackObservation = nil
      if let observer = self.timeObserver { self.player.removeTimeObserver(observer) }
      self.player = AVPlayer()
      self.observePlayer()
      self.interrupted = false
      self.errorMessage = "系统音频服务已重置，请重新开始播放"
      self.publish()
    })
    let commands = MPRemoteCommandCenter.shared()
    commands.playCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async { self?.resumeFromRemote() }
      return .success
    }
    commands.pauseCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async { self?.pause() }
      return .success
    }
    commands.togglePlayPauseCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if self.wantsPlayback { self.pause() } else { self.resumeFromRemote() }
      }
      return .success
    }
    commands.stopCommand.addTarget { [weak self] _ in
      DispatchQueue.main.async { self?.stop() }
      return .success
    }
    commands.changePlaybackPositionCommand.isEnabled = false
    commands.nextTrackCommand.isEnabled = false
    commands.previousTrackCommand.isEnabled = false
  }

  private func observePlayer() {
    player.actionAtItemEnd = .pause
    playbackObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        if self.player.timeControlStatus == .playing { self.endBackgroundTask() }
        self.publish()
      }
    }
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
      self?.updateNowPlaying()
    }
  }

  private func activateSession() throws {
    beforeAudioStart?()
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .spokenAudio, options: [])
    try session.setActive(true)
  }

  private func smoothCommand(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    commandRevision += 1
    let revision = commandRevision
    let volume = player.volume
    for step in 1...3 {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.004) { [weak self] in
        guard let self = self else { return }
        guard revision == self.commandRevision else {
          if step == 3 { result(FlutterError(code: "superseded", message: "已切换播放请求", details: nil)) }
          return
        }
        self.player.volume = volume * (1 - Float(step) / 3)
        if step == 3 {
          do {
            if call.method == "start" { try self.start(call.arguments) } else { self.stop() }
            self.player.volume = 1
            result(self.snapshot())
          } catch {
            self.player.volume = 1
            result(FlutterError(code: "lesson_audio", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }

  private func start(_ arguments: Any?) throws {
    guard let args = arguments as? [String: Any],
          let newLesson = args["lesson"] as? String,
          let rows = args["clips"] as? [[String: Any]], !rows.isEmpty else {
      throw playbackError("音频队列不可用")
    }
    let newClips = rows.compactMap { row -> Clip? in
      guard let id = row["id"] as? String,
            let file = row["path"] as? String,
            FileManager.default.fileExists(atPath: file) else { return nil }
      return Clip(id: id, path: file)
    }
    guard newClips.count == rows.count else { throw playbackError("音频文件缺失，请重新下载教材") }
    guard !blockedBooks.contains(where: { newLesson.hasPrefix($0 + ":") }) else {
      throw playbackError("教材正在更新，暂时不能播放")
    }
    try activateSession()
    interrupted = false
    stop(deactivate: false)
    clips = newClips
    index = min(max(0, args["startIndex"] as? Int ?? 0), clips.count - 1)
    lesson = newLesson
    title = args["title"] as? String ?? "课程学习"
    words = args["words"] as? Bool ?? true
    albumTitle = args["albumTitle"] as? String ?? (words ? "单词" : "课文")
    batch = args["batch"] as? Bool ?? false
    speed = min(3, max(0.5, (args["speed"] as? NSNumber)?.floatValue ?? 1))
    repeatCount = min(5, max(1, args["repeat"] as? Int ?? 1))
    intervalSteps = min(10, max(0, args["intervalSteps"] as? Int ?? 0))
    wantsPlayback = true
    prepareClip()
  }

  private func prepareClip() {
    guard !clips.isEmpty else { return }
    if wantsPlayback && !interrupted { beginBackgroundTask() }
    currentClip?.asset.cancelLoading()
    let prepared: PreparedClip
    if let next = nextClip, next.index == index {
      prepared = next
    } else {
      nextClip?.asset.cancelLoading()
      prepared = loadClip(at: index)
    }
    nextClip = nil
    currentClip = prepared
    preparing = true
    itemObservation = nil
    installPreparedClip(prepared)
    preloadNextClip()
    publish()
  }

  private func preloadNextClip() {
    guard batch, !clips.isEmpty, currentClip != nil else { return }
    let nextIndex = repetition + 1 < repeatCount ? index : (index + 1) % clips.count
    if nextClip?.index == nextIndex { return }
    nextClip?.asset.cancelLoading()
    nextClip = loadClip(at: nextIndex)
  }

  private func loadClip(at index: Int) -> PreparedClip {
    let prepared = PreparedClip(index: index, path: clips[index].path)
    let asset = prepared.asset
    let token = generation
    // Keep only the current occurrence and one successor, including repeats.
    // An unattached item preloads timing/mix data, not the player's decoder.
    asset.loadValuesAsynchronously(forKeys: ["duration", "tracks"]) { [weak self] in
      DispatchQueue.main.async {
        guard let self = self, token == self.generation,
              prepared === self.currentClip || prepared === self.nextClip else { return }
        guard asset.statusOfValue(forKey: "duration", error: nil) == .loaded,
              asset.statusOfValue(forKey: "tracks", error: nil) == .loaded else {
          prepared.error = "音频时长或音轨读取失败，请检查教材资源"
          if prepared === self.currentClip { self.installPreparedClip(prepared) }
          return
        }
        self.prepareLoadedClip(prepared)
        if prepared === self.currentClip { self.installPreparedClip(prepared) }
      }
    }
    return prepared
  }

  private func prepareLoadedClip(_ prepared: PreparedClip) {
    let asset = prepared.asset
    let duration = asset.duration.seconds
    let start = 0.0
    let end = duration
    let tracks = asset.tracks(withMediaType: .audio)
    guard duration.isFinite, end > start, !tracks.isEmpty else {
      prepared.error = "音频文件无有效时长或没有可播放音轨"
      return
    }
    // Keep the media-timed fade-in; preserve the original volume at the end.
    let fadeIn = min(0.010, (end - start) / 2)
    func time(_ seconds: Double) -> CMTime {
      CMTime(seconds: seconds, preferredTimescale: 60000)
    }
    let mix = AVMutableAudioMix()
    mix.inputParameters = tracks.map { track in
      let parameters = AVMutableAudioMixInputParameters(track: track)
      parameters.setVolume(0, at: .zero)
      parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1,
        timeRange: CMTimeRange(start: time(start), duration: time(fadeIn)))
      return parameters
    }
    let item = AVPlayerItem(asset: asset)
    item.audioTimePitchAlgorithm = .timeDomain
    item.audioMix = mix
    prepared.item = item
  }

  private func installPreparedClip(_ prepared: PreparedClip) {
    guard prepared === currentClip else { return }
    if let error = prepared.error { fail(error); return }
    guard let item = prepared.item, item !== player.currentItem else { return }
    let token = generation
    player.replaceCurrentItem(with: item)
    // Each occurrence owns a fresh item at time zero; no seek is needed.
    // During a configured gap this also lets the player prepare the next item.
    itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      DispatchQueue.main.async {
        guard let self = self, token == self.generation,
              item === self.currentClip?.item, item === self.player.currentItem else { return }
        if item.status == .failed {
          self.fail("音频读取失败，请检查教材资源后重新开始")
          return
        }
        guard item.status == .readyToPlay, self.preparing else { return }
        self.preparing = false
        self.playPreparedClip()
        self.publish()
      }
    }
  }

  private func playPreparedClip() {
    guard !clips.isEmpty, !preparing, gapRemaining == nil else { return }
    if wantsPlayback && !interrupted {
      player.playImmediately(atRate: speed)
    } else {
      endBackgroundTask()
    }
  }

  private func finishClip() {
    guard !clips.isEmpty, gapRemaining == nil, !preparing else { return }
    if !batch { stop(completed: clips[index].id); return }
    // Advance only on the native end event, never on elapsed wall-clock time.
    repetition += 1
    if repetition >= repeatCount {
      repetition = 0
      index = (index + 1) % clips.count
    }
    gapRemaining = Double(intervalSteps) * 0.5
    // Install/finish preparing the successor while the requested gap elapses.
    prepareClip()
    if wantsPlayback && !interrupted { scheduleGap() }
    publish()
  }

  private func scheduleGap() {
    guard let remaining = gapRemaining else { return }
    beginBackgroundTask()
    gapTimer?.invalidate()
    if remaining <= 0 {
      finishGap()
      return
    }
    gapDeadline = Date().addingTimeInterval(remaining)
    let token = generation
    gapTimer = Timer.scheduledTimer(withTimeInterval: remaining, repeats: false) { [weak self] _ in
      guard let self = self, token == self.generation, self.wantsPlayback, !self.interrupted else { return }
      self.finishGap()
    }
  }

  private func finishGap() {
    gapRemaining = nil
    gapDeadline = nil
    gapTimer = nil
    playPreparedClip()
    publish()
  }

  private func suspendPlayback() {
    player.pause()
    if let deadline = gapDeadline { gapRemaining = max(0, deadline.timeIntervalSinceNow) }
    gapTimer?.invalidate()
    gapTimer = nil
    gapDeadline = nil
    endBackgroundTask()
  }

  private func pause() {
    wantsPlayback = false
    suspendPlayback()
    publish()
  }

  private func resume() throws {
    guard !clips.isEmpty else { return }
    guard !blockedBooks.contains(where: { lesson.hasPrefix($0 + ":") }) else {
      throw playbackError("教材正在更新，暂时不能播放")
    }
    try activateSession()
    interrupted = false
    errorMessage = nil
    wantsPlayback = true
    beginBackgroundTask()
    if gapRemaining != nil {
      scheduleGap()
    } else if !preparing {
      player.playImmediately(atRate: speed)
    }
    publish()
  }

  private func resumeFromRemote() {
    do { try resume() } catch {
      errorMessage = "暂时无法继续播放，请在音频中断结束后重试"
      publish()
    }
  }

  private func handleInterruption(_ notification: Notification) {
    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    if type == .began {
      interrupted = true
      suspendPlayback()
      publish()
    } else {
      let options = AVAudioSession.InterruptionOptions(rawValue:
        notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
      interrupted = false
      if wantsPlayback && options.contains(.shouldResume) {
        do { try resume() } catch {
          wantsPlayback = false
          errorMessage = "音频中断已结束，请点击继续播放"
          publish()
        }
      } else {
        wantsPlayback = false
        publish()
      }
    }
  }

  private func stop(deactivate: Bool = true, completed: String? = nil) {
    let hadAudio = !clips.isEmpty
    completedClipId = completed
    generation += 1
    wantsPlayback = false
    suspendPlayback()
    itemObservation = nil
    currentClip?.asset.cancelLoading()
    nextClip?.asset.cancelLoading()
    currentClip = nil
    nextClip = nil
    player.replaceCurrentItem(with: nil)
    clips = []
    index = 0
    repetition = 0
    batch = false
    preparing = false
    gapRemaining = nil
    errorMessage = nil
    if deactivate && hadAudio {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    publish()
  }

  private func fail(_ message: String) {
    stop()
    errorMessage = message
    publish()
  }

  private func playbackError(_ message: String) -> NSError {
    NSError(domain: "LessonPlayback", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
  }

  private func beginBackgroundTask() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Lesson audio transition") { [weak self] in
      self?.pause()
    }
  }

  private func endBackgroundTask() {
    if backgroundTask != .invalid {
      UIApplication.shared.endBackgroundTask(backgroundTask)
      backgroundTask = .invalid
    }
  }

  private func snapshot() -> [String: Any] {
    var state: [String: Any] = [
      "revision": revision,
      "lesson": lesson, "words": words, "active": !clips.isEmpty,
      "title": title, "waiting": gapRemaining != nil,
      "isPlaying": !clips.isEmpty && player.timeControlStatus == .playing && wantsPlayback && !interrupted && gapRemaining == nil,
      "batch": batch, "paused": !wantsPlayback || interrupted,
      "interrupted": interrupted, "repeat": repeatCount, "intervalSteps": intervalSteps,
    ]
    if !clips.isEmpty {
      // `index` advances before an optional interval starts, so Dart can retain
      // the correct next batch start even if playback is stopped in that gap.
      state["queuedId"] = clips[index].id
      if gapRemaining == nil { state["playingId"] = clips[index].id }
    }
    if let error = errorMessage { state["error"] = error }
    if let completed = completedClipId { state["completedId"] = completed }
    return state
  }

  private func publish() {
    revision += 1
    updateNowPlaying()
    channel.invokeMethod("state", arguments: snapshot())
  }

  private func updateNowPlaying() {
    guard !clips.isEmpty else {
      MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
      return
    }
    let duration = player.currentItem?.duration.seconds ?? 0
    let safeDuration = duration.isFinite ? max(0, duration) : 0
    let position = player.currentTime().seconds
    MPNowPlayingInfoCenter.default().nowPlayingInfo = [
      MPMediaItemPropertyTitle: title,
      MPMediaItemPropertyAlbumTitle: albumTitle,
      MPMediaItemPropertyPlaybackDuration: safeDuration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime:
        gapRemaining == nil && position.isFinite ? min(safeDuration, max(0, position)) : 0,
      MPNowPlayingInfoPropertyPlaybackRate: player.timeControlStatus == .playing ? speed : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
    ]
  }
}
