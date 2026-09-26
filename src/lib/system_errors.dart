import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'user_error.dart';

/// Local diagnostics only. Reporting never throws or waits on the app write queue.
class SystemErrors {
  static Database? _database;
  static final List<Map<String, Object?>> _pending = [];
  static final Expando<StackTrace> _reported = Expando<StackTrace>();
  static Future<void>? _flushing;
  static Future<void> _operations = Future<void>.value();
  static String? userId, appVersion;
  static final String sessionId = DateTime.now().microsecondsSinceEpoch.toString();

  static void attach(Database database) {
    _database = database;
    unawaited(flush());
  }

  static String _safe(Object? value, {int limit = 32768}) {
    var text = value?.toString() ?? '';
    // Preserve exception type, SQL and paths, but omit credentials and SQL values.
    text = text.replaceAll(RegExp(r'arguments\s*\[.*', dotAll: true, caseSensitive: false), 'arguments [已隐藏]');
    text = text.replaceAllMapped(
      RegExp(r'''((?:password|passwd|pwd|token|authorization|secret|ciphertext|密码|密文)["']?\s*[:=]\s*)(?:"[^"]*"|'[^']*'|[^\s,;}]+)''', caseSensitive: false),
      (match) => '${match[1]}[已隐藏]',
    );
    text = text.replaceAllMapped(RegExp(r'https?://[^\s<>"\x27]+'), (match) {
      final uri = Uri.tryParse(match[0]!);
      if (uri == null) return '[地址格式异常]';
      return uri.replace(userInfo: '', query: '', fragment: '').toString();
    });
    return text.length <= limit ? text : '${text.substring(0, limit)}\n[内容过长，已截断]';
  }

  static void record(Object error, StackTrace stack, {
    required String module,
    required String operation,
    String? hint,
    String severity = 'error',
    Map<String, Object?> context = const {},
  }) {
    try {
      // A rethrow through several reporting boundaries is still one incident.
      if (error is Exception || error is Error) {
        if (identical(_reported[error], stack)) return;
        _reported[error] = stack;
      }
      final details = <String, String>{};
      for (final entry in context.entries) {
        details[entry.key] = RegExp('password|passwd|token|authorization|secret|ciphertext|密码|密文', caseSensitive: false).hasMatch(entry.key)
            ? '[已隐藏]' : _safe(entry.value, limit: 4096);
      }
      _pending.add({
        'occurred_at': DateTime.now().millisecondsSinceEpoch,
        'session_id': sessionId, 'user_id': userId, 'app_version': appVersion,
        'platform': Platform.operatingSystem,
        'os_version': _safe(Platform.operatingSystemVersion, limit: 1024),
        'severity': severity, 'module': module, 'operation': operation,
        'user_hint': hint ?? userError(error),
        'error_type': error.runtimeType.toString(),
        'error_code': error is PlatformException ? error.code
            : error is OSError ? error.errorCode.toString() : null,
        'message': _safe(error), 'stack_trace': _safe(stack, limit: 65536),
        'context_json': jsonEncode(details),
      });
      // Bound memory when storage is unavailable. Never recurse on log failures.
      if (_pending.length > 100) _pending.removeAt(0);
      unawaited(flush());
    } catch (_) { /* Diagnostic failures must not replace the original error. */ }
  }

  static Future<void> _enqueue(Future<void> Function() action) {
    final result = _operations.then((_) => action());
    _operations = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Future<void> flush() => _flushing ??= _enqueue(_drain).whenComplete(() => _flushing = null);

  static Future<void> deleteAll() => _enqueue(() async {
    final database = _database;
    if (database == null) throw StateError('系统信息数据库尚未打开');
    // Remove queued old reports only after SQL succeeds. Reports arriving while
    // deletion is in progress remain eligible for the next flush.
    final previous = Set<Map<String, Object?>>.identity()..addAll(_pending);
    await database.delete('yzc_system_error');
    _pending.removeWhere(previous.contains);
  });

  static Future<void> pruneOnLogin() async {
    try {
      await _enqueue(() async {
        final database = _database;
        if (database == null) return;
        await _drain();
        await database.transaction((tx) async {
          final rows = await tx.rawQuery('SELECT COUNT(*) AS count FROM yzc_system_error');
          if ((rows.single['count'] as int) <= 100) return;
          await tx.rawDelete('''DELETE FROM yzc_system_error WHERE id NOT IN (
            SELECT id FROM yzc_system_error ORDER BY occurred_at DESC,id DESC LIMIT 10
          )''');
        });
      });
    } catch (_) {
      // Maintenance must neither interrupt login nor generate recursive logs.
      // A later app launch retries the count and cleanup.
    }
  }

  static Future<void> _drain() async {
    final database = _database;
    if (database == null) return;
    while (_pending.isNotEmpty) {
      final row = _pending.first;
      try {
        await database.insert('yzc_system_error', row);
        // New reports may evict the oldest pending row during an awaited write.
        if (_pending.isNotEmpty && identical(_pending.first, row)) _pending.removeAt(0);
      } catch (_) {
        return; // Retry on the next report or when opening the records page.
      }
    }
  }
}
