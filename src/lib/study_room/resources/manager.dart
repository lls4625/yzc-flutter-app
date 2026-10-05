import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../../data.dart';
import 'config.dart';
import 'extractor.dart';
import '../../system_errors.dart';
import '../jlpt/feature/content.dart';

String _quote(String name) => '"${name.replaceAll('"', '""')}"';

Future<bool> _studyEntityExists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.notFound;

Future<void> _deleteStudyEntity(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.directory) {
    await Directory(path).delete(recursive: true);
  } else if (type == FileSystemEntityType.file) {
    await File(path).delete();
  } else if (type == FileSystemEntityType.link) {
    await Link(path).delete();
  }
}

Future<void> _moveStudyEntity(String source, String target) async {
  final type = await FileSystemEntity.type(source, followLinks: false);
  if (type == FileSystemEntityType.notFound) throw FileSystemException('自习资源路径不存在', source);
  await Directory(target).parent.create(recursive: true);
  if (await _studyEntityExists(target)) await _deleteStudyEntity(target);
  if (type == FileSystemEntityType.directory) {
    await Directory(source).rename(target);
  } else if (type == FileSystemEntityType.file) {
    await File(source).rename(target);
  } else if (type == FileSystemEntityType.link) {
    await Link(source).rename(target);
  } else {
    throw FileSystemException('自习资源路径类型不受支持', source);
  }
}

class StudyResources extends ChangeNotifier {
  StudyResources(this.store);
  final AppStore store;
  static const levels = ['n1', 'n2', 'n3', 'n4', 'n5'];
  bool checking = false, busy = false;
  double? progress;
  String message = '', error = '';
  bool permissionError = false, errorNeedsRecheck = false;
  String? activeLevel;
  final Map<String, Map<String, dynamic>> _installed = {};
  Map<String, Map<String, dynamic>> _remote = {};
  Set<String> _invalidRemoteHashes = {};
  final Map<String, String> _installedDates = {};
  final Set<String> _available = {}, _cleanup = {};
  bool hasPublishedCatalog = false;
  Future<void>? _checking;
  Map<String, int> questionCounts = {};
  final Map<String, ({int audio, int images})> attachmentCounts = {};
  String infoError = '';
  bool get ready => _available.isNotEmpty;
  bool hasLocalData(String level) {
    final id = level.toLowerCase();
    return _installed.containsKey(id) || _available.contains(id) ||
        _cleanup.contains(id) || questionCounts.containsKey(id.toUpperCase());
  }
  List<String> get visibleLevels {
    final remote = hasPublishedCatalog
        ? _remote.keys.toList(growable: false)
        : <String>[];
    final remoteIds = remote.toSet();
    return <String>[
      ...remote,
      for (final level in levels)
        if (hasLocalData(level) && !remoteIds.contains(level)) level,
    ];
  }
  bool get hasUpdate => levels.any(hasLevelUpdate);
  bool isReady(String level) => _available.contains(level.toLowerCase());
  bool isPublished(String level) => hasPublishedCatalog && _remote.containsKey(level.toLowerCase());
  bool hasInvalidHash(String level) => _invalidRemoteHashes.contains(level.toLowerCase());
  bool canDownload(String level) {
    final id = level.toLowerCase();
    final hash = _remote[id]?['sha256'];
    return hash is String && hash.trim().isNotEmpty && !_invalidRemoteHashes.contains(id);
  }
  String? textbook(String level) {
    final id = level.toLowerCase();
    return (_remote[id] ?? _installed[id])?['textbook'] as String?;
  }
  void clearError() {
    error = ''; permissionError = false; errorNeedsRecheck = false;
    notifyListeners();
  }

  Future<void> _networkFailure(Object cause) async {
    errorNeedsRecheck = cause is SocketException || cause is HttpException ||
        cause is HandshakeException || cause is TimeoutException;
    permissionError = false;
    if (!errorNeedsRecheck) return;
    _remote = {};
    _invalidRemoteHashes = {};
    hasPublishedCatalog = false;
    try {
      final status = await const MethodChannel('yuzhichu/device')
          .invokeMapMethod<String, Object?>('networkStatus')
          .timeout(const Duration(seconds: 3));
      permissionError = status?['status'] == 'unavailable' &&
          const ['wifiDenied', 'cellularDenied'].contains(status?['reason']);
      if (permissionError) error = '当前网络访问受限，请检查系统设置中“语之初”的无线数据设置，或切换到可用的 Wi-Fi。';
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'selfstudy', operation: '读取网络状态');
    }
  }
  bool hasLevelUpdate(String level) {
    final id = level.toLowerCase();
    final remoteHash = _remote[id]?['sha256'];
    return isReady(id) && remoteHash is String && remoteHash != _installed[id]?['sha256'];
  }
  bool needsCleanup(String level) => _cleanup.contains(level.toLowerCase());
  String? installedAt(String level) => _installedDates[level.toLowerCase()];
  Directory get directory => Directory('${store.root.path}/study');
  File get localManifest => File('${directory.path}/study_local.json');

  /// References are relative to the installed level package's mp3 directory.
  Future<String?> mediaPath(String level, String reference) async {
    final id = level.toLowerCase();
    final parts = reference.split('/');
    if (!isReady(id) || busy || reference.isEmpty ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..' ||
          part.contains('\\') || part.contains(':') || part.contains('\u0000'))) return null;
    final hash = _installed[id]?['sha256'];
    if (hash == null) return null;
    final file = File('${directory.path}/resources/$id/$hash/$reference');
    return await file.exists() ? file.path : null;
  }

  Future<void> _excludeDownloadsFromBackup() async {
    if (Platform.isIOS) {
      await const MethodChannel('yuzhichu/device')
          .invokeMethod<void>('excludeDownloadedResourcesFromBackup');
    }
  }

  Future<void> initialize() async {
    try {
      await _excludeDownloadsFromBackup();
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'selfstudy', operation: '设置资源备份属性');
    }
    await directory.create(recursive: true);
    await _recoverMediaSwaps();
    await _restoreReceipts();
    for (final level in levels) { await _tryCleanup(level); }
    await refreshInfo();
  }

  Future<void> refreshInfo() async {
    try {
      final rows = await store.db.rawQuery('''SELECT q.level, COUNT(*) AS count
        FROM stydy_jlpt_question q
        WHERE NOT EXISTS (SELECT 1 FROM stydy_jlpt_question newer
          WHERE newer.id=q.id AND newer.version>q.version)
        GROUP BY q.level''');
      questionCounts = {for (final row in rows) textOf(row, 'level'): intOf(row, 'count')};
      infoError = '';
    } catch (e, stack) {
      questionCounts = {};
      infoError = '题库信息读取失败，请刷新重试';
      SystemErrors.record(e, stack, module: 'selfstudy', operation: '读取题库数量');
    }
    await _refreshAttachmentCounts();
    notifyListeners();
  }

  Future<void> _refreshAttachmentCounts() async {
    attachmentCounts.clear();
    for (final level in levels.where(isReady)) {
      final hash = _installed[level]?['sha256'];
      if (hash == null) continue;
      try {
        var audio = 0, images = 0;
        final media = Directory('${directory.path}/resources/$level/$hash');
        await for (final entry in media.list(recursive: true, followLinks: false)) {
          if (entry is! File) continue;
          final name = entry.uri.pathSegments.last.toLowerCase();
          if (name.startsWith('.')) continue;
          final extension = name.split('.').last;
          if (const {'mp3', 'm4a', 'aac', 'wav', 'aif', 'aiff', 'caf', 'flac', 'ogg', 'opus'}.contains(extension)) {
            audio++;
          } else if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg', 'avif', 'tif', 'tiff'}.contains(extension)) {
            images++;
          }
        }
        attachmentCounts[level] = (audio: audio, images: images);
      } catch (e, stack) {
        SystemErrors.record(e, stack, module: 'selfstudy', operation: '读取附件数量', context: {'level': level});
      }
    }
  }

  Future<void> _restoreReceipts() async {
    final rows = await store.db.query('stydy_resource_install');
    final installed = <String, Map<String, dynamic>>{};
    final dates = <String, String>{};
    final available = <String>{};
    for (final row in rows) {
      final level = textOf(row, 'id');
      if (!levels.contains(level)) continue;
      final descriptor = _descriptors(textOf(row, 'manifest_json'));
      if (descriptor.length != 1 || !descriptor.containsKey(level)) {
        throw const FormatException('本地级别安装记录无效');
      }
      installed[level] = descriptor[level]!;
      dates[level] = textOf(row, 'installed_at');
      if (await Directory('${directory.path}/resources/$level/${descriptor[level]!['sha256']}').exists()) {
        available.add(level);
      }
    }
    _installed..clear()..addAll(installed);
    _installedDates..clear()..addAll(dates);
    _available..clear()..addAll(available);
    await _publish(jsonEncode([for (final level in levels)
      if (_installed.containsKey(level)) _installed[level]]));
  }

  Future<void> _tryCleanup(String level) async {
    try {
      final root = Directory('${directory.path}/resources/$level');
      final keep = _installed[level]?['sha256'];
      if (await root.exists()) {
        await for (final entry in root.list(followLinks: false)) {
          if (keep == null || entry.path != '${root.path}/$keep') {
            await entry.delete(recursive: true);
          }
        }
        if (keep == null) await root.delete();
      }
      final staging = Directory('${directory.path}/staging/$level');
      if (await staging.exists()) await staging.delete(recursive: true);
      _cleanup.remove(level);
    } catch (e, stack) {
      _cleanup.add(level);
      SystemErrors.record(e, stack, module: 'selfstudy', operation: '清理级别资源文件', context: {'level': level});
    }
  }

  Future<void> _recoverMediaSwaps() async {
    for (final level in levels) {
      final root = Directory('${directory.path}/resources/$level');
      if (!await root.exists()) continue;
      await for (final entry in root.list(followLinks: false)) {
        final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
        final match = RegExp(r'^\.replace-([a-f0-9]{64})$').firstMatch(name);
        if (match == null) continue;
        final target = '${root.path}/${match.group(1)}';
        if (await _studyEntityExists(target)) {
          await _deleteStudyEntity(entry.path);
        } else {
          await _moveStudyEntity(entry.path, target);
        }
      }
    }
  }

  Future<void> _deleteLevel(DatabaseExecutor tx, String level) async {
    final value = level.toUpperCase();
    // Delete paper items before their owning papers; the other levels stay intact.
    await tx.rawDelete('''DELETE FROM stydy_jlpt_paper_item
      WHERE EXISTS (SELECT 1 FROM stydy_jlpt_paper p
        WHERE p.id=stydy_jlpt_paper_item.paper_id
        AND p.version=stydy_jlpt_paper_item.paper_version AND p.level=?)''', [value]);
    for (final table in ['stydy_jlpt_paper', 'stydy_jlpt_question', 'stydy_jlpt_blueprint']) {
      await tx.delete(table, where: 'level=?', whereArgs: [value]);
    }
  }

  Future<void> cleanup(String level) async {
    if (busy || !levels.contains(level)) return;
    busy = true; activeLevel = level; error = ''; permissionError = false; errorNeedsRecheck = false; _report('清理资源文件');
    try {
      await _checking;
      await _restoreReceipts();
      await _tryCleanup(level);
      await refreshInfo();
      if (needsCleanup(level)) {
        error = '资源文件清理失败，请重试。';
      } else {
        _report('资源文件已清理', 1);
      }
    } catch (e, stack) {
      _cleanup.add(level);
      error = '本地资源同步失败，请重试。';
      SystemErrors.record(e, stack, module: 'selfstudy', operation: '重试资源清理', context: {'level': level});
    } finally { busy = false; activeLevel = null; notifyListeners(); }
  }

  Future<void> remove(String level) async {
    if (busy || !levels.contains(level)) return;
    busy = true; activeLevel = level; error = ''; permissionError = false; errorNeedsRecheck = false; _report('删除 ${level.toUpperCase()} 题库');
    var committed = false;
    try {
      await _checking;
      await store.write(() => store.db.transaction((tx) async {
        await _deleteLevel(tx, level);
        await tx.delete('stydy_resource_install', where: 'id=?', whereArgs: [level]);
      }));
      committed = true;
      await _restoreReceipts();
      await _tryCleanup(level);
      await refreshInfo();
      if (needsCleanup(level)) {
        error = '题库已删除，部分资源文件清理失败，请重试清理。';
      } else {
        _report('${level.toUpperCase()} 题库已删除', 1);
      }
    } catch (e, stack) {
      if (committed) { _installed.remove(level); _available.remove(level); _installedDates.remove(level); _cleanup.add(level); }
      error = committed ? '题库已删除，本地文件同步未完成，请重试清理。' : '题库删除失败，请重试。';
      SystemErrors.record(e, stack, module: 'selfstudy', operation: '删除题库', context: {'level': level, 'committed': committed});
    } finally { busy = false; activeLevel = null; notifyListeners(); }
  }

  ({Map<String, Map<String, dynamic>> rows, Set<String> invalidHashes})
      _parseDescriptors(String text, {required bool catalog}) {
    final json = jsonDecode(text);
    if (json is! List) throw const FormatException('自习资源目录必须是数组');
    final result = <String, Map<String, dynamic>>{};
    final invalidHashes = <String>{};
    for (final value in json) {
      if (value is! Map) throw const FormatException('自习资源目录无效');
      final row = Map<String, dynamic>.from(value);
      final id = row['id'];
      if (id is! String || !levels.contains(id) || result.containsKey(id) ||
          row['resource_file'] != '$id.zip') {
        throw const FormatException('自习资源 ID 或文件名无效');
      }
      final hash = row['sha256'];
      if (hash == null || (hash is String && hash.trim().isEmpty)) {
        if (!catalog) throw const FormatException('本地自习资源摘要无效');
        row['sha256'] = null;
      } else if (hash is String && RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash)) {
        row['sha256'] = hash.toLowerCase();
      } else {
        if (!catalog) throw const FormatException('本地自习资源摘要无效');
        row['sha256'] = null;
        invalidHashes.add(id);
      }
      result[id] = row;
    }
    return (rows: result, invalidHashes: invalidHashes);
  }

  Map<String, Map<String, dynamic>> _descriptors(String text) =>
      _parseDescriptors(text, catalog: false).rows;

  ({Map<String, Map<String, dynamic>> rows, Set<String> invalidHashes})
      _catalogDescriptors(String text) => _parseDescriptors(text, catalog: true);

  Future<String> _fetchManifest() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final uri = StudyResourceConfig.base.resolve('study.json')
        .replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'});
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw HttpException('自习资源目录获取失败（HTTP ${response.statusCode}）', uri: uri);
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) throw const FormatException('自习资源目录过大');
      }
      final text = utf8.decode(bytes);
      _catalogDescriptors(text);
      return text;
    } finally { client.close(force: true); }
  }

  Future<void> check() {
    if (busy) return Future.value();
    return _checking ??= _check().whenComplete(() => _checking = null);
  }
  Future<void> _check() async {
    checking = true; error = ''; permissionError = false; errorNeedsRecheck = false;
    _remote = {};
    _invalidRemoteHashes = {};
    hasPublishedCatalog = false;
    notifyListeners();
    try {
      await _restoreReceipts();
      await refreshInfo();
      final catalog = _catalogDescriptors(await _fetchManifest());
      _remote = catalog.rows;
      _invalidRemoteHashes = catalog.invalidHashes;
      hasPublishedCatalog = true;
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'selfstudy', operation: '检查资源更新', context: {'base_url': StudyResourceConfig.baseUrl});
      final hasLocal = levels.any(hasLocalData);
      error = ready
          ? '暂时无法检查更新，已下载资源仍可使用。'
          : hasLocal
              ? '暂时无法检查更新，本地资源仍可管理。'
              : '无法获取自习资源，请检查网络后重试。';
      _remote = {};
      _invalidRemoteHashes = {};
      hasPublishedCatalog = false;
      await _networkFailure(e);
      errorNeedsRecheck = true;
    } finally { checking = false; notifyListeners(); }
  }

  void _report(String text, [double? value]) {
    message = text; progress = value; notifyListeners();
  }

  Future<void> _publish(String text) async {
    final file = File('${localManifest.path}.tmp');
    await file.writeAsString(text, encoding: utf8, flush: true);
    await file.rename(localManifest.path);
  }

  Future<void> install(String level) async {
    if (busy || !levels.contains(level)) return;
    busy = true; activeLevel = level; error = ''; permissionError = false; errorNeedsRecheck = false; _report('获取 ${level.toUpperCase()} 资源信息');
    Database? source;
    Directory? staging;
    String? mediaPath;
    String? mediaBackupPath;
    bool mediaPlaced = false;
    bool committed = false;
    String? oldManifest;
    final diagnostics = <String, Object?>{'base_url': StudyResourceConfig.baseUrl, 'resource_file': '$level.zip'};
    try {
      await _checking;
      await _restoreReceipts();
      oldManifest = await localManifest.readAsString(encoding: utf8);
      final manifest = await _fetchManifest();
      final catalog = _catalogDescriptors(manifest);
      _remote = catalog.rows;
      _invalidRemoteHashes = catalog.invalidHashes;
      hasPublishedCatalog = true;
      if (_invalidRemoteHashes.contains(level)) {
        _report('资源信息校验失败', 1);
        return;
      }
      final descriptor = _remote[level];
      if (descriptor == null) throw StateError('${level.toUpperCase()} 资源已从服务器移除');
      final catalogHash = descriptor['sha256'];
      diagnostics['catalog_sha256'] = catalogHash;
      if (isReady(level) && (catalogHash == null || catalogHash == _installed[level]?['sha256'])) {
        _report('该级别资源已是最新版本', 1); return;
      }
      staging = Directory('${directory.path}/staging/$level/${store.newId()}');
      await staging.create(recursive: true);
      await _excludeDownloadsFromBackup();
      await File('${staging.path}/study.json').writeAsString(manifest, encoding: utf8, flush: true);
      final zip = File('${staging.path}/$level.zip');
      await _download(zip, descriptor['resource_file'] as String);
      _report('准备自习资源');
      final actualHash = (await sha256.bind(zip.openRead()).first).toString();
      final installedDescriptor = Map<String, dynamic>.from(descriptor)..['sha256'] = actualHash;
      diagnostics['actual_sha256'] = actualHash;
      diagnostics['zip_path'] = zip.path;
      diagnostics['downloaded_bytes'] = await zip.length();
      await _extract(zip, '${staging.path}/extracted', level);
      source = await openDatabase('${staging.path}/extracted/$level/data.sqlite', readOnly: true, singleInstance: false);
      _report('读取资源数据');
      final sourceDb = source;
      final schemas = <String, List<Map<String, Object?>>>{};
      for (final table in studyContentTables) {
        final definition = await sourceDb.rawQuery(
          'SELECT type FROM sqlite_master WHERE name=?', [table]);
        if (definition.length != 1 || definition.single['type'] != 'table') {
          throw FormatException('资源包缺少数据表 $table');
        }
        final columns = await sourceDb.rawQuery('PRAGMA table_info(${_quote(table)})');
        if (columns.isEmpty) throw FormatException('资源包缺少 $table');
        schemas[table] = columns;
      }
      for (final table in ['stydy_jlpt_question', 'stydy_jlpt_blueprint', 'stydy_jlpt_paper']) {
        final foreign = await sourceDb.query(table, columns: ['id'],
          where: 'level IS NULL OR level<>?', whereArgs: [level.toUpperCase()], limit: 1);
        if (foreign.isNotEmpty) throw const FormatException('资源包包含其他级别或无级别的数据');
      }
      await validateStudyContent(sourceDb);
      // The validated download is authoritative. Keep the occupied target only
      // as a short-lived rollback copy until the database receipt commits.
      mediaPath = '${directory.path}/resources/$level/$actualHash';
      mediaBackupPath = '${directory.path}/resources/$level/.replace-$actualHash';
      await Directory(mediaPath).parent.create(recursive: true);
      if (await _studyEntityExists(mediaBackupPath)) await _deleteStudyEntity(mediaBackupPath);
      if (await _studyEntityExists(mediaPath)) await _moveStudyEntity(mediaPath, mediaBackupPath);
      await _moveStudyEntity('${staging.path}/extracted/$level/mp3', mediaPath);
      mediaPlaced = true;
      await _excludeDownloadsFromBackup();
      _report('导入自习资源');
      await store.write(() => store.db.transaction((tx) async {
        await _deleteLevel(tx, level);
        for (final table in studyContentTables) {
          final columns = schemas[table]!;
          final local = await tx.rawQuery('PRAGMA table_info(${_quote(table)})');
          final localDefinition = await tx.rawQuery('SELECT sql FROM sqlite_master WHERE type=? AND name=?', ['table', table]);
          final hasOldConstraints = localDefinition.isNotEmpty &&
              RegExp(r'\b(CHECK|FOREIGN|REFERENCES|UNIQUE)\b', caseSensitive: false)
                .hasMatch(localDefinition.single['sql']?.toString() ?? '');
          String signature(List<Map<String, Object?>> rows) => jsonEncode([for (final c in rows)
            [c['name'], c['type'], c['pk'], c['dflt_value']]]);
          if (signature(local) != signature(columns) || hasOldConstraints) {
            final remaining = await tx.query(table, limit: 1);
            if (remaining.isNotEmpty) throw const FormatException('题库结构发生变化，无法保留其他级别，请使用匹配版本的资源包');
            await tx.execute('DROP TABLE IF EXISTS ${_quote(table)}');
            await tx.execute(_createTable(table, columns));
          }
          for (var offset = 0; ; offset += 200) {
            final rows = await sourceDb.query(table, limit: 200, offset: offset);
            if (table != 'stydy_jlpt_paper_item' && rows.isNotEmpty) {
              final ids = rows.map((row) => row['id']).toSet().toList();
              final conflicts = await tx.query(table, columns: ['id'],
                where: 'id IN (${List.filled(ids.length, '?').join(',')}) AND level<>?',
                whereArgs: [...ids, level.toUpperCase()], limit: 1);
              if (conflicts.isNotEmpty) throw const FormatException('不同级别不能使用相同的题目、模板或试卷 ID');
            }
            final batch = tx.batch();
            for (final row in rows) { batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort); }
            await batch.commit(noResult: true);
            if (rows.length < 200) break;
          }
          // Replace only this table's ordinary indexes, never execute source DDL.
          final indexes = await tx.rawQuery('PRAGMA index_list(${_quote(table)})');
          for (final index in indexes.where((i) => i['origin'] == 'c')) {
            await tx.execute('DROP INDEX ${_quote(index['name'] as String)}');
          }
          final sourceIndexes = await sourceDb.rawQuery('PRAGMA index_list(${_quote(table)})');
          var number = 0;
          for (final index in sourceIndexes.where((i) => i['origin'] != 'pk')) {
            final entries = await sourceDb.rawQuery('PRAGMA index_info(${_quote(index['name'] as String)})');
            if (entries.isEmpty || entries.any((e) => e['name'] is! String)) {
              throw const FormatException('资源索引不受支持');
            }
            await tx.execute('CREATE INDEX ${_quote('${table}_resource_${number++}')} ON ${_quote(table)} '
              '(${entries.map((e) => _quote(e['name'] as String)).join(',')})');
          }
        }
        await tx.insert('stydy_resource_install', {
          'id': level, 'manifest_json': jsonEncode([installedDescriptor]), 'installed_at': DateTime.now().toUtc().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        // Failure here rolls back all four tables. Startup reconciles the file
        // from the receipt if the process exits before this transaction commits.
        await _publish(jsonEncode([for (final id in levels)
          if (id == level) installedDescriptor else if (_installed.containsKey(id)) _installed[id]]));
      }));
      committed = true;
      if (await _studyEntityExists(mediaBackupPath)) await _deleteStudyEntity(mediaBackupPath);
      await _restoreReceipts();
      await refreshInfo();
      _report('${level.toUpperCase()} 资源安装完成', 1);
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'selfstudy', operation: '下载并安装自习资源', context: {...diagnostics, 'stage': message, 'staging': staging?.path, 'committed': committed});
      if (!committed && oldManifest != null) {
        try { await _publish(oldManifest); } catch (cleanupError, cleanupStack) {
          SystemErrors.record(cleanupError, cleanupStack, module: 'selfstudy', operation: '恢复与清理自习资源', context: {'stage': message, 'staging': staging?.path});
          /* Startup restores from the committed receipt. */
        }
      }
      if (!committed && mediaPath != null) {
        try {
          if (mediaBackupPath != null && await _studyEntityExists(mediaBackupPath)) {
            if (await _studyEntityExists(mediaPath)) await _deleteStudyEntity(mediaPath);
            await _moveStudyEntity(mediaBackupPath, mediaPath);
          } else if (mediaPlaced && await _studyEntityExists(mediaPath)) {
            await _deleteStudyEntity(mediaPath);
          }
        } catch (cleanupError, cleanupStack) {
          SystemErrors.record(cleanupError, cleanupStack, module: 'selfstudy', operation: '恢复被替换的自习资源', context: {'level': level, 'media': mediaPath, 'backup': mediaBackupPath});
        }
      }
      error = committed ? '资源已安装，本地文件同步未完成，请重新打开资源页。'
          : isReady(level) ? '该级别更新失败，原有资源和学习记录已保留。' : '该级别下载失败，请重试。';
      await _networkFailure(e);
    } finally {
      try { await source?.close(); } catch (cleanupError, cleanupStack) {
        SystemErrors.record(cleanupError, cleanupStack, module: 'selfstudy', operation: '恢复与清理自习资源', context: {'stage': message, 'staging': staging?.path});
      }
      try { if (staging != null && await staging.exists()) await staging.delete(recursive: true); } catch (cleanupError, cleanupStack) {
        SystemErrors.record(cleanupError, cleanupStack, module: 'selfstudy', operation: '恢复与清理自习资源', context: {'stage': message, 'staging': staging?.path});
      }
      // Read the committed receipt before removing obsolete or failed media.
      try {
        await _restoreReceipts();
        await _tryCleanup(level);
        if (needsCleanup(level)) {
          error = [error, '部分资源文件清理失败，请重试清理。'].where((value) => value.isNotEmpty).join('\n');
        }
      } catch (e, stack) {
        _cleanup.add(level);
        if (error.isEmpty) error = '本地安装记录同步未完成，请重试清理。';
        SystemErrors.record(e, stack, module: 'selfstudy', operation: '恢复级别安装记录', context: {'level': level});
      }
      busy = false; activeLevel = null; notifyListeners();
    }
  }

  String _createTable(String name, List<Map<String, Object?>> columns) {
    final keys = columns.where((c) => (c['pk'] as int) > 0).toList()
      ..sort((a, b) => (a['pk'] as int).compareTo(b['pk'] as int));
    if (keys.isEmpty) throw const FormatException('资源表缺少主键');
    final fields = <String>[];
    for (final column in columns) {
      final type = column['type'] as String;
      final fallback = column['dflt_value'];
      if (!RegExp(r'^[a-zA-Z0-9_ (),]*$').hasMatch(type) ||
          (fallback != null && (fallback.toString().contains(';') || fallback.toString().contains('--')))) {
        throw const FormatException('资源表字段定义不受支持');
      }
      fields.add('${_quote(column['name'] as String)} $type'
        '${(column['pk'] as int) > 0 ? ' NOT NULL' : ''}'
        '${fallback == null ? '' : ' DEFAULT $fallback'}');
    }
    fields.add('PRIMARY KEY (${keys.map((c) => _quote(c['name'] as String)).join(',')})');
    return 'CREATE TABLE ${_quote(name)} (${fields.join(',')})';
  }

  Future<void> _download(File file, String filename) async {
    _report('下载自习资源');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20)..autoUncompress = false;
    IOSink? sink;
    try {
      final capacity = await const MethodChannel('yuzhichu/device').invokeMethod<int>('freeSpace');
      final uri = StudyResourceConfig.base.resolve(filename)
        .replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'});
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw HttpException('资源下载失败（HTTP ${response.statusCode}）', uri: uri);
      final size = response.contentLength;
      sink = file.openWrite(); var received = 0;
      await for (final bytes in response.timeout(const Duration(seconds: 30))) {
        received += bytes.length;
        if (size >= 0 && received > size) throw const FormatException('资源下载长度异常');
        if (received > 2 * 1024 * 1024 * 1024 ||
            (capacity != null && capacity < received * 4 + 128 * 1024 * 1024)) {
          throw const FileSystemException('自习资源超过可用空间');
        }
        sink.add(bytes); await sink.flush();
        _report('下载自习资源', size > 0 ? received / size : null);
      }
      if (received == 0 || (size >= 0 && size != received)) throw const FormatException('资源下载不完整');
    } finally { await sink?.close(); client.close(force: true); }
  }

  Future<void> _extract(File zip, String destination, String level) async {
    _report('解压自习资源');
    final password = await StudyResourceConfig.restorePassword();
    final capacity = await const MethodChannel('yuzhichu/device').invokeMethod<int>('freeSpace');
    final messages = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
    final done = Completer<void>();
    final subscription = messages.listen((dynamic value) {
      final m = value as Map;
      if (m['progress'] is num) _report('解压自习资源', (m['progress'] as num).toDouble());
      if (m['error'] != null && !done.isCompleted) done.completeError(StateError('解压失败：${m['error']}'), StackTrace.fromString(m['stack']?.toString() ?? '子进程未提供堆栈'));
      if (m['done'] == true && !done.isCompleted) done.complete();
    });
    final errorSubscription = errors.listen((dynamic e) {
      if (!done.isCompleted) done.completeError(StateError('解压进程失败：${e is List && e.isNotEmpty ? e.first : e}'), e is List && e.length > 1 ? StackTrace.fromString(e[1].toString()) : StackTrace.current);
    });
    final exitSubscription = exits.listen((_) {
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (!done.isCompleted) done.completeError(StateError('解压进程中断'));
      });
    });
    Isolate? worker;
    try {
      worker = await Isolate.spawn(extractStudyWorker,
        <Object>[messages.sendPort, zip.path, destination, level, password, capacity ?? -1],
        onError: errors.sendPort, onExit: exits.sendPort);
      await done.future;
    } finally {
      worker?.kill(priority: Isolate.immediate);
      await subscription.cancel(); await errorSubscription.cancel(); await exitSubscription.cancel();
      messages.close(); errors.close(); exits.close();
    }
  }
}
