import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../config.dart';
import '../../data.dart';
import '../../system_errors.dart';

class NoticeConfig {
  static Uri get url => ResourceConfig.base.resolve('../notice/data.json');
}

class AppNotice {
  AppNotice(this.json) {
    for (final key in ['id', 'title', 'content', 'type']) {
      if (json[key] is! String || (json[key] as String).trim().isEmpty) {
        throw FormatException('公告字段无效：$key');
      }
    }
    for (final key in ['closeDelaySeconds', 'repeatCount']) {
      if (json[key] is! int || (json[key] as int) < (key == 'repeatCount' ? 1 : 0)) {
        throw FormatException('公告字段无效：$key');
      }
    }
    if (json['enabled'] is! bool || json['repeatEnabled'] is! bool) {
      throw const FormatException('公告开关无效');
    }
    publishedAt = _date(json['publishedAt']);
    expiresAt = json['expiresAt'] == null ? null : _date(json['expiresAt']);
    if (expiresAt != null && !expiresAt!.isAfter(publishedAt)) {
      throw const FormatException('公告过期时间必须晚于发布时间');
    }
  }
  static DateTime _date(Object? value) {
    if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw const FormatException('公告时间必须包含时区');
    }
    return DateTime.parse(value);
  }
  final Map<String, dynamic> json;
  late final DateTime publishedAt;
  late final DateTime? expiresAt;
  String get id => json['id'] as String;
  String get title => json['title'] as String;
  String get content => json['content'] as String;
  String get type => json['type'] as String;
  int get delay => json['closeDelaySeconds'] as int;
  int get target => json['repeatEnabled'] == true ? json['repeatCount'] as int : 1;
  bool active(DateTime now) => json['enabled'] == true &&
      !publishedAt.isAfter(now) && (expiresAt == null || expiresAt!.isAfter(now));
}

class NoticeService extends ChangeNotifier {
  NoticeService(this.store);
  final AppStore store;
  List<AppNotice> notices = [];
  final Map<String, int> confirmations = {};
  final Set<String> dismissedIds = {};
  Future<void>? _initializing;
  Future<void>? _refreshing;
  String? _etag;
  String? _source;
  String? loadError;

  int count(AppNotice notice) => confirmations[notice.id] ?? 0;
  bool isDismissed(AppNotice notice) => dismissedIds.contains(notice.id);
  Iterable<AppNotice> get visibleNotices => notices.where((notice) => !isDismissed(notice));
  AppNotice? get latest {
    final now = DateTime.now();
    for (final notice in visibleNotices) {
      if (notice.active(now)) return notice;
    }
    return null;
  }

  List<AppNotice> _parse(String body) {
    final data = jsonDecode(body);
    if (data is! Map || data['schemaVersion'] != 1 || data['notices'] is! List) {
      throw const FormatException('公告数据格式或版本无效');
    }
    final result = <AppNotice>[];
    final ids = <String>{};
    for (final item in data['notices'] as List) {
      if (item is! Map<String, dynamic>) throw const FormatException('公告格式无效');
      final notice = AppNotice(item);
      if (!ids.add(notice.id)) throw const FormatException('公告 ID 重复');
      result.add(notice);
    }
    result.sort((a, b) {
      final order = b.publishedAt.compareTo(a.publishedAt);
      return order == 0 ? b.id.compareTo(a.id) : order;
    });
    return result;
  }

  Future<void> initialize() => _initializing ??= _load().catchError((Object e, StackTrace s) {
    _initializing = null;
    loadError = '通知暂时无法读取，请下次打开时重试。';
    SystemErrors.record(e, s, module: 'notice', operation: '读取本地公告');
    notifyListeners();
    throw e;
  });

  Future<void> _load() async {
    _source = NoticeConfig.url.toString();
    final rows = await store.db.query('yzc_notice_cache', where: 'source = ?', whereArgs: [_source]);
    if (rows.isNotEmpty) {
      try {
        notices = _parse(rows.single['body'] as String);
        _etag = rows.single['etag'] as String?;
      } catch (e, s) {
        // A damaged cache must not prevent a fresh download or erase confirmations.
        notices = [];
        _etag = null;
        SystemErrors.record(e, s, module: 'notice', operation: '读取公告缓存');
      }
    }
    final counts = await store.db.query('yzc_notice_confirmation');
    for (final row in counts) {
      confirmations[row['notice_id'] as String] = row['count'] as int;
    }
    final dismissals = await store.db.query('yzc_notice_dismissal');
    dismissedIds
      ..clear()
      ..addAll(dismissals.map((row) => row['notice_id'] as String));
    loadError = null;
    notifyListeners();
  }

  Future<void> refresh() => _refreshing ??= _sync().whenComplete(() => _refreshing = null);

  Future<void> _sync() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
    try {
      await initialize();
      await _download(client).timeout(const Duration(seconds: 12));
      loadError = null;
    } catch (e, s) {
      loadError = '暂时无法获取最新通知，已保留本地内容。';
      SystemErrors.record(e, s, module: 'notice', operation: '同步公告');
    } finally {
      client.close(force: true);
      notifyListeners();
    }
  }

  Future<void> _download(HttpClient client) async {
    final request = await client.getUrl(NoticeConfig.url);
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    if (_etag != null) request.headers.set(HttpHeaders.ifNoneMatchHeader, _etag!);
    final response = await request.close();
    if (response.statusCode == HttpStatus.notModified && _etag != null) {
      await response.drain<void>();
      return;
    }
    if (response.statusCode != HttpStatus.ok) throw HttpException('Notice HTTP ${response.statusCode}');
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) throw const FormatException('公告文件超过 2 MB');
    }
    final body = utf8.decode(bytes);
    final parsed = _parse(body);
    final etag = response.headers.value(HttpHeaders.etagHeader);
    await store.write(() => store.db.transaction((tx) async {
      await tx.rawInsert('INSERT OR REPLACE INTO yzc_notice_cache(source, body, etag) VALUES (?, ?, ?)', [_source, body, etag]);
    }));
    notices = parsed;
    _etag = etag;
  }

  Future<void> confirm(AppNotice notice) async {
    await initialize();
    await store.write(() async {
      final next = count(notice) + 1;
      await store.db.rawInsert('INSERT OR REPLACE INTO yzc_notice_confirmation(notice_id, count) VALUES (?, ?)', [notice.id, next]);
      confirmations[notice.id] = next;
    });
    notifyListeners();
  }

  /// Hides this server-supplied notice on the current device only.
  Future<void> dismiss(AppNotice notice) async {
    await initialize();
    await store.write(() async {
      await store.db.rawInsert(
        'INSERT OR REPLACE INTO yzc_notice_dismissal(notice_id, dismissed_at) VALUES (?, ?)',
        [notice.id, nowMs()],
      );
      dismissedIds.add(notice.id);
    });
    notifyListeners();
  }
}
