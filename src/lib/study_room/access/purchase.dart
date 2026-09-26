import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../system_errors.dart';

/// Entitlements come exclusively from verified StoreKit transactions.
class StudyRoomPurchaseController extends ChangeNotifier
    with WidgetsBindingObserver {
  StudyRoomPurchaseController() {
    _channel.setMethodCallHandler(_onNativeCall);
    WidgetsBinding.instance.addObserver(this);
  }

  static const _channel = MethodChannel('yuzhichu/study_room_purchase');
  bool _unlocked = false, _busy = false, _loadingProduct = false;
  bool _initialized = false, _disposed = false, _canPay = false;
  bool _productRequested = false;
  int _revision = -1;
  String? _price, _message;
  bool get unlocked => _unlocked;
  bool get initialized => _initialized;
  // Rechecking existing access must not interrupt an unlocked study session.
  bool get saving => !_unlocked && (!_initialized || _busy);
  bool get busy => _busy;
  bool get loadingProduct => _loadingProduct;
  String? get price => _price;
  String? get message => _message;
  bool get canPurchase => _initialized && !_busy && !_loadingProduct && !_unlocked &&
      _canPay && _price != null;
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _apply(Object? value) {
    if (_disposed || value is! Map) return;
    final revision = (value['revision'] as num?)?.toInt() ?? -1;
    if (revision < _revision) return;
    _revision = revision;
    _unlocked = value['unlocked'] == true;
    _canPay = value['canPay'] == true;
    _price = value['price'] as String?;
    _message = value['message'] as String?;
    _initialized = true;
    _notify();
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'state') _apply(call.arguments);
  }

  void _record(Object error, StackTrace stack, String operation) {
    SystemErrors.record(error, stack, module: 'selfstudy_access', operation: operation);
    _message = error is PlatformException
        ? error.message ?? '购买服务暂不可用，请稍后重试'
        : '购买服务暂不可用，请稍后重试';
    _notify();
  }

  Future<void> reload() async {
    if (_disposed) return;
    if (!supported) {
      _initialized = true;
      _message = '请在 iPhone 或 iPad 上购买或恢复购买';
      _notify();
      return;
    }
    try {
      _apply(await _channel.invokeMethod<Object?>('refresh'));
    } catch (error, stack) {
      _record(error, stack, '读取自习室购买权益');
    } finally {
      _initialized = true;
      _notify();
    }
    // Product lookup may need the network; never hold up app/database loading.
    if (!_productRequested && !_disposed) unawaited(loadProduct());
  }

  Future<void> loadProduct() async {
    if (_disposed || !supported || _loadingProduct || _busy) return;
    _productRequested = true;
    _loadingProduct = true;
    _notify();
    try {
      _apply(await _channel.invokeMethod<Object?>('loadProduct'));
    } catch (error, stack) {
      _record(error, stack, '读取自习室内购商品');
    } finally {
      _loadingProduct = false;
      _notify();
    }
  }

  Future<void> purchase() async {
    if (!canPurchase) return;
    await _perform('purchase', '购买自习室');
  }

  Future<void> restore() async {
    if (_disposed || !supported || _busy) return;
    await _perform('restore', '恢复自习室购买');
  }

  Future<void> _perform(String method, String operation) async {
    _busy = true;
    _message = null;
    _notify();
    try {
      _apply(await _channel.invokeMethod<Object?>(method));
    } catch (error, stack) {
      _record(error, stack, operation);
    } finally {
      _busy = false;
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(reload());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
