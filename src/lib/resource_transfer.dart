import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'resource_archive_extractor.dart';

class ResourceCancelled implements Exception {
  const ResourceCancelled();
}

class ResourceHashMismatch implements Exception {
  const ResourceHashMismatch();
}

class ResourceHttpException extends HttpException {
  ResourceHttpException(this.status, Uri uri)
    : super('资源请求失败（HTTP $status）', uri: uri);
  final int status;
}

/// Cancellation never races a database transaction. Native work is awaited;
/// checkpoints inside the transaction throw so SQLite can roll it back first.
class ResourceTask {
  ResourceTask({Duration deadline = const Duration(minutes: 45)}) {
    _timer = Timer(deadline, () => abort(TimeoutException('资源处理超时')));
  }
  late final Timer _timer;
  final Set<void Function()> _aborters = {};
  Object? _reason;
  bool _finished = false;
  bool get cancelled => _reason is ResourceCancelled;
  bool get stopped => _reason != null;
  bool get canCancel => !_finished && !stopped;
  void check() {
    if (_reason case final Object reason) throw reason;
  }

  void cancel() => abort(const ResourceCancelled());
  void abort(Object reason) {
    if (_finished || _reason != null) return;
    _reason = reason;
    for (final abort in _aborters.toList()) {
      abort();
    }
  }

  void Function() onAbort(void Function() abort) {
    check();
    _aborters.add(abort);
    return () => _aborters.remove(abort);
  }

  Future<void> delay(Duration duration) async {
    check();
    final done = Completer<void>();
    final timer = Timer(duration, done.complete);
    final remove = onAbort(() {
      if (!done.isCompleted) done.complete();
    });
    try {
      await done.future;
      check();
    } finally {
      timer.cancel();
      remove();
    }
  }

  void finish() {
    _finished = true;
    _timer.cancel();
    _aborters.clear();
  }
}

typedef ResourceProgress = void Function(
  String stage,
  double? value,
  String detail,
);

/// Shared bounded transport for textbooks and self-study. Partial bytes never
/// leave staging, and retries restart the file rather than append to it.
class ResourceTransfer {
  ResourceTransfer({
    this.attempts = 3,
    this.requestTimeout = const Duration(seconds: 20),
    this.idleTimeout = const Duration(seconds: 30),
    this.downloadTimeout = const Duration(minutes: 15),
    this.extractTimeout = const Duration(minutes: 10),
    this.retryDelay = const Duration(seconds: 1),
    this.maxBytes = 2 * 1024 * 1024 * 1024,
    Future<int?> Function()? freeSpace,
  }) : _freeSpace = freeSpace;
  final int attempts, maxBytes;
  final Duration requestTimeout,
      idleTimeout,
      downloadTimeout,
      extractTimeout,
      retryDelay;
  final Future<int?> Function()? _freeSpace;
  static const reserve = 128 * 1024 * 1024;

  Future<int?> capacity() async {
    if (_freeSpace != null) return _freeSpace().timeout(requestTimeout);
    try {
      return await const MethodChannel('yuzhichu/device')
          .invokeMethod<int>('freeSpace')
          .timeout(const Duration(seconds: 5));
    } on MissingPluginException {
      return null; // Desktop tools may not expose the iOS capacity channel.
    }
  }

  bool _transient(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      (error is ResourceHttpException &&
          const {408, 429, 500, 502, 503, 504}.contains(error.status)) ||
      (error is HttpException && error is! ResourceHttpException);

  Future<T> _retry<T>(
    ResourceTask task,
    ResourceProgress report,
    Future<T> Function() body,
  ) async {
    for (var attempt = 1; ; attempt++) {
      task.check();
      try {
        return await body();
      } catch (error) {
        task.check();
        if (attempt >= attempts || !_transient(error)) rethrow;
        report('retry', null, '连接中断，正在重试 ${attempt + 1}/$attempts（可取消）');
        await task.delay(retryDelay * attempt);
      }
    }
  }

  Future<T> _request<T>(
    Uri uri,
    ResourceTask task,
    Duration limit,
    Future<T> Function(HttpClientResponse) consume,
  ) async {
    task.check();
    final client = HttpClient()
      ..connectionTimeout = requestTimeout
      ..autoUncompress = false;
    var expired = false;
    final timer = Timer(limit, () {
      expired = true;
      client.close(force: true);
    });
    final remove = task.onAbort(() => client.close(force: true));
    try {
      final request = await client
          .getUrl(
            uri.replace(
              queryParameters: {
                ...uri.queryParameters,
                't': '${DateTime.now().microsecondsSinceEpoch}',
              },
            ),
          )
          .timeout(requestTimeout);
      task.check();
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(requestTimeout);
      task.check();
      if (response.statusCode != 200)
        throw ResourceHttpException(response.statusCode, uri);
      final encoding = response.headers.value(
        HttpHeaders.contentEncodingHeader,
      );
      if (encoding != null && encoding.toLowerCase() != 'identity') {
        throw const FormatException('资源响应编码不受支持');
      }
      final result = await consume(response);
      task.check();
      if (expired) throw TimeoutException('资源下载超时');
      return result;
    } catch (_) {
      task.check();
      if (expired) throw TimeoutException('资源下载超时');
      rethrow;
    } finally {
      timer.cancel();
      remove();
      client.close(force: true);
    }
  }

  Future<Object?> json(
    Uri uri, {
    ResourceTask? task,
    ResourceProgress? report,
    int limit = 8 * 1024 * 1024,
  }) async {
    final current = task ?? ResourceTask(deadline: const Duration(minutes: 2));
    try {
      return await _retry(
        current,
        report ?? (_, _, _) {},
        () => _request(uri, current, const Duration(seconds: 45), (
          response,
        ) async {
          final bytes = <int>[];
          await for (final chunk in response.timeout(idleTimeout)) {
            current.check();
            bytes.addAll(chunk);
            if (bytes.length > limit) throw const FormatException('资源目录过大');
          }
          current.check();
          return jsonDecode(utf8.decode(bytes));
        }),
      );
    } finally {
      if (task == null) current.finish();
    }
  }

  Future<String> download(
    Uri uri,
    File file,
    ResourceTask task,
    ResourceProgress report, {
    String? expectedHash,
  }) async {
    final space = await capacity();
    task.check();
    if (space != null && space < reserve) throw StateError('可用存储空间不足');
    await _retry(task, report, () async {
      report('download', null, '正在连接下载服务器');
      RandomAccessFile? output;
      try {
        await _request(uri, task, downloadTimeout, (response) async {
          final expected = response.contentLength;
          if (expected > maxBytes) throw const FormatException('资源包超过大小限制');
          if (expected == 0) throw const FormatException('下载文件为空');
          if (space != null && expected > 0 && space < expected * 3 + reserve) {
            throw StateError('可用存储空间不足');
          }
          output = await file.open(mode: FileMode.write);
          var received = 0;
          await for (final bytes in response.timeout(idleTimeout)) {
            task.check();
            received += bytes.length;
            if (received > maxBytes || (expected >= 0 && received > expected)) {
              throw const FormatException('资源下载长度异常');
            }
            if (space != null && space < received * 3 + reserve)
              throw StateError('可用存储空间不足');
            await output!.writeFrom(bytes);
            report(
              'download',
              expected > 0 ? received / expected : null,
              expected > 0 ? '$received / $expected 字节' : '已下载 $received 字节',
            );
          }
          if (received == 0 || (expected >= 0 && received != expected)) {
            throw const HttpException('资源下载不完整');
          }
          task.check();
          await output!.flush();
        });
      } finally {
        await output?.close();
      }
    });
    report('verify', null, '正在校验资源包');
    final digest = await sha256
        .bind(
          file.openRead().map((bytes) {
            task.check();
            return bytes;
          }),
        )
        .first;
    task.check();
    final hash = digest.toString();
    if (expectedHash != null &&
        expectedHash.isNotEmpty &&
        hash != expectedHash.toLowerCase()) {
      throw const ResourceHashMismatch();
    }
    return hash;
  }

  Future<void> extract(
    File zip,
    String destination,
    String folder,
    String password,
    ResourceTask task,
    ResourceProgress report,
  ) async {
    final space = await capacity();
    task.check();
    report('extract', 0, '正在解压资源');
    task.check();
    final messages = ReceivePort(),
        errors = ReceivePort(),
        exits = ReceivePort();
    final done = Completer<void>();
    final exited = Completer<void>();
    Isolate? worker;
    void fail(Object error, [StackTrace? stack]) {
      if (!done.isCompleted)
        done.completeError(error, stack ?? StackTrace.current);
    }

    final subscription = messages.listen((dynamic value) {
      if (done.isCompleted || task.stopped || value is! Map) return;
      if (value['progress'] is num)
        report('extract', (value['progress'] as num).toDouble(), '正在解压资源');
      if (value['error'] != null) fail(StateError('解压失败：${value['error']}'));
      if (value['done'] == true && !done.isCompleted) done.complete();
    });
    final errorSubscription = errors.listen(
      (dynamic value) => fail(StateError('解压进程失败：$value')),
    );
    final exitSubscription = exits.listen((_) {
      if (!exited.isCompleted) exited.complete();
      // done and exit are delivered on separate ports; allow done to drain.
      Timer(const Duration(milliseconds: 100), () {
        if (!done.isCompleted) fail(StateError('解压进程中断'));
      });
    });
    final timer = Timer(extractTimeout, () {
      worker?.kill(priority: Isolate.immediate);
      fail(TimeoutException('资源解压超时'));
    });
    final remove = task.onAbort(() {
      worker?.kill(priority: Isolate.immediate);
      try {
        task.check();
      } catch (error) {
        fail(error);
      }
    });
    // Attach an error handler before spawn, since cancellation may win that await.
    final waiting = done.future;
    unawaited(waiting.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    try {
      worker = await Isolate.spawn(
        extractResourceArchiveWorker,
        <Object>[
          messages.sendPort,
          zip.path,
          destination,
          folder,
          password,
          space ?? -1,
        ],
        onError: errors.sendPort,
        onExit: exits.sendPort,
      );
      if (task.stopped || done.isCompleted)
        worker.kill(priority: Isolate.immediate);
      await waiting;
      task.check();
    } finally {
      timer.cancel();
      remove();
      worker?.kill(priority: Isolate.immediate);
      // Never delete staging until the writer isolate has really exited.
      if (worker != null) await exited.future;
      await subscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      messages.close();
      errors.close();
      exits.close();
    }
  }
}
