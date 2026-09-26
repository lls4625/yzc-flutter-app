import 'system_errors.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'config.dart';

class StartupNetworkResult {
  const StartupNetworkResult(this.ready, this.title, this.detail, {this.permissionDenied = false, this.networkError = false});
  final bool ready;
  final bool permissionDenied;
  final bool networkError;
  final String title;
  final String detail;
}

/// Checks the public textbook service only when its page requests it.
class StartupNetwork {
  static const _channel = MethodChannel('yuzhichu/device');

  Future<bool> openSettings() async {
    bool opened = false;
    try {
      opened = await _channel.invokeMethod<bool>('openSettings') ?? false;
    } on PlatformException catch (e, stack) {
      SystemErrors.record(e, stack, module: 'network', operation: '网络检查与设置', context: {'base_url': ResourceConfig.baseUrl});
    } on MissingPluginException catch (e, stack) {
      SystemErrors.record(e, stack, module: 'network', operation: '网络检查与设置', context: {'base_url': ResourceConfig.baseUrl});
    }
    return opened;
  }

  Future<StartupNetworkResult> checkServer() async {
    final Uri uri;
    try {
      uri = ResourceConfig.base.resolve('yzc_textbook.json');
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'network', operation: '网络检查与设置', context: {'base_url': ResourceConfig.baseUrl});
      return const StartupNetworkResult(false, '教材服务地址无效', '请联系维护者检查教材服务配置。');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      await _readCatalog(client, uri).timeout(const Duration(seconds: 12));
      return const StartupNetworkResult(true, '教材服务已连接', '可以获取教材目录和下载教材。');
    } on HttpException catch (e, stack) {
      SystemErrors.record(e, stack, module: 'network', operation: '网络检查与设置', context: {'base_url': ResourceConfig.baseUrl});
      return const StartupNetworkResult(false, '教材服务暂时不可用', '已连接到服务，但未能获取教材目录。请稍后重试或联系维护者。', networkError: true);
    } on FormatException catch (e, stack) {
      SystemErrors.record(e, stack, module: 'network', operation: '网络检查与设置', context: {'base_url': ResourceConfig.baseUrl});
      return const StartupNetworkResult(false, '教材目录暂时不可用', '服务返回的目录格式异常，请稍后重试或联系维护者。');
    } on HandshakeException catch (e, stack) {
      SystemErrors.record(e, stack, module: 'network', operation: '网络检查与设置', context: {'base_url': ResourceConfig.baseUrl});
      return const StartupNetworkResult(false, '无法安全连接教材服务', '请联系维护者检查服务证书。', networkError: true);
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'network', operation: '网络检查与设置', context: {'base_url': ResourceConfig.baseUrl});
      final status = await _status();
      if (status['status'] == 'unavailable' &&
          (status['reason'] == 'wifiDenied' || status['reason'] == 'cellularDenied')) {
        return const StartupNetworkResult(false, '当前网络访问受限',
          '请检查系统设置中“语之初”的无线数据设置，或切换到可用的 Wi-Fi。已下载教材可继续离线使用。',
          permissionDenied: true, networkError: true);
      }
      if (status['status'] == 'unavailable') {
        return const StartupNetworkResult(false, '网络不可用，无法连接教材服务器',
          '请检查 Wi-Fi 或蜂窝网络后重试。已下载教材可继续离线使用。', networkError: true);
      }
      return const StartupNetworkResult(false, '教材服务器连接异常',
        '请检查网络连接，稍后重试。已下载教材可继续离线使用。', networkError: true);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _readCatalog(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) throw HttpException('Catalog unavailable (HTTP ${response.statusCode})', uri: uri);
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 8 * 1024 * 1024) throw const FormatException('Catalog too large');
    }
    if (jsonDecode(utf8.decode(bytes)) is! List) throw const FormatException('Invalid catalog');
  }

  Future<Map<String, Object?>> _status() async {
    try {
      return await _channel.invokeMapMethod<String, Object?>('networkStatus')
          .timeout(const Duration(seconds: 3)) ?? {};
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'network', operation: '网络检查与设置', context: {'base_url': ResourceConfig.baseUrl});
      return {};
    }
  }
}
