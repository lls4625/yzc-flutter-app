import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'config.dart';
import 'data.dart';
import 'ios_lesson_playback.dart';
import 'ai_question.dart';
import 'resource_archive_extractor.dart';
import 'system_errors.dart';
import 'course/feature/image_interaction_config.dart';

const textbookContentTables = ['yzc_unit', 'yzc_lessons', 'yzc_words', 'yzc_content', 'yzc_grammar', 'yzc_ai_question'];
void safeName(String name) {
  if (name.isEmpty || name == '.' || name == '..' || name.contains('/') || name.contains('\\') || name.contains(':') || name.contains('\u0000') || name.startsWith('.')) throw const FormatException('资源文件名无效');
}

Future<bool> _resourceEntityExists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.notFound;

Future<void> _deleteResourceEntity(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.directory) {
    await Directory(path).delete(recursive: true);
  } else if (type == FileSystemEntityType.file) {
    await File(path).delete();
  } else if (type == FileSystemEntityType.link) {
    await Link(path).delete();
  }
}

Future<void> _moveResourceEntity(String source, String target) async {
  final type = await FileSystemEntity.type(source, followLinks: false);
  if (type == FileSystemEntityType.notFound) throw FileSystemException('资源路径不存在', source);
  await Directory(target).parent.create(recursive: true);
  if (await _resourceEntityExists(target)) await _deleteResourceEntity(target);
  if (type == FileSystemEntityType.directory) {
    await Directory(source).rename(target);
  } else if (type == FileSystemEntityType.file) {
    await File(source).rename(target);
  } else if (type == FileSystemEntityType.link) {
    await Link(source).rename(target);
  } else {
    throw FileSystemException('资源路径类型不受支持', source);
  }
}

String textbookMediaFilename(String source, String type) {
  final parts = source.split('/');
  if (parts.length != 2 || parts.first != 'mp3') throw const FormatException('内容媒体必须位于 mp3 文件夹');
  final filename = parts.last;
  safeName(filename);
  final extension = filename.split('.').last.toLowerCase();
  final allowed = switch (type) {
    'image' || 'interactive_image' => {'png', 'jpg', 'jpeg', 'webp'},
    'video' => {'mp4'},
    'audio' => {'mp3'},
    _ => <String>{},
  };
  if (!allowed.contains(extension)) throw const FormatException('内容媒体类型或格式不受支持');
  return filename;
}

class Resources extends ChangeNotifier {
  Resources(this.store);
  final AppStore store;
  String? activeBook;
  String stage = '', detail = '';
  double? progress;
  final Set<String> unavailable = {};
  Map<String, RowData> _publishedTextbooks = {};
  Set<String> _invalidPublishedTextbookHashes = {};
  bool hasPublishedCatalog = false;
  List<RowData> get publishedTextbooks => _publishedTextbooks.values.toList();
  RowData? publishedTextbook(String id) => _publishedTextbooks[id];
  bool hasInvalidPublishedTextbookHash(String id) => _invalidPublishedTextbookHashes.contains(id);
  void clearPublishedTextbooks() {
    _publishedTextbooks = {};
    _invalidPublishedTextbookHashes = {};
    hasPublishedCatalog = false;
  }
  DateTime _lastNotice = DateTime.fromMillisecondsSinceEpoch(0);
  void report(String next, double? value, [String message = '']) {
    final changed = next != stage;
    stage = next; progress = value; detail = message;
    if (changed || value == 1 || DateTime.now().difference(_lastNotice).inMilliseconds > 80) {
      _lastNotice = DateTime.now(); notifyListeners();
    }
  }
  Future<RowData?> installation(String id) async {
    final rows = await installations(id: id);
    return rows.isEmpty ? null : rows.single;
  }
  Future<List<RowData>> installations({String? id}) => store.db.rawQuery(
    "SELECT i.*,o.sha256 FROM yzc_resource_install i LEFT JOIN yzc_resource_operation o ON o.id=i.job_id AND o.textbook_id=i.textbook_id AND o.action='download' AND o.status='success'${id == null ? '' : ' WHERE i.textbook_id=?'}",
    [if (id != null) id],
  );

  Future<String> _beginOperation(String book, String action) async {
    final id = store.newId(), time = nowMs();
    await store.write(() => store.db.insert('yzc_resource_operation', {
      'id': id, 'textbook_id': book, 'action': action, 'status': 'running',
      'phase': 'started', 'create_time': time, 'update_time': time,
    }));
    return id;
  }

  Future<void> _failOperation(String id, Object error) => store.write(() async {
    final time = nowMs();
    await store.db.update('yzc_resource_operation', {
      'status': 'failed', 'error': error.toString(), 'update_time': time, 'finish_time': time,
    }, where: 'id=? AND status=?', whereArgs: [id, 'running']);
  });
  Future<String> audioPath(String book, String filename) async {
    safeName(filename);
    if (unavailable.contains(book)) throw StateError('内容正在同步或需要修复');
    final row = await installation(book);
    if (row == null || row['status'] != 'ready') throw StateError('请先下载内容');
    final folder = textOf(row, 'folder'); safeName(folder);
    final path = '${store.root.path}/resources/$folder/mp3/$filename';
    if (!await File(path).exists()) throw StateError('音频文件缺失，请重新下载内容');
    return path;
  }
  Future<String> mediaPath(String book, String source, String type) async {
    final filename = textbookMediaFilename(source, type);
    if (unavailable.contains(book) || activeBook == book) throw StateError('内容正在同步或需要修复');
    final row = await installation(book);
    if (row == null || row['status'] != 'ready') throw StateError('请先下载内容');
    final folder = textOf(row, 'folder'); safeName(folder);
    final root = Directory('${store.root.path}/resources/$folder/mp3');
    final file = File('${root.path}/$filename');
    if (!await file.exists()) throw StateError('媒体文件缺失，请重新下载内容');
    final rootPath = await root.resolveSymbolicLinks();
    final path = await file.resolveSymbolicLinks();
    if (File(path).parent.path != rootPath) throw const FormatException('内容媒体路径无效');
    return path;
  }
  Future<Object?> _json(String name) async {
    final uri = ResourceConfig.base.resolve(name).replace(queryParameters: {'t': '${nowMs()}'});
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw HttpException('$name 获取失败（${response.statusCode}）');
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 20))) {
        bytes.addAll(chunk);
        if (bytes.length > 8 * 1024 * 1024) throw const FormatException('目录文件过大');
      }
      return jsonDecode(utf8.decode(bytes));
    } finally { client.close(force: true); }
  }
  Future<List<RowData>> refreshTextbooks() async {
    final json = await _json('yzc_textbook.json');
    if (json is! List) throw const FormatException('内容目录必须是数组');
    final columns = await store.db.rawQuery('PRAGMA table_info(yzc_textbook)');
    final keys = columns.map((r) => r['name'] as String).toSet();
    final rows = <String, RowData>{};
    final invalidHashes = <String>{};
    for (final entry in json) {
      if (entry is! Map || entry['id'] is! String || (entry['id'] as String).isEmpty || rows.containsKey(entry['id'])) {
        throw const FormatException('内容 ID 必须为唯一字符串');
      }
      final id = entry['id'] as String;
      final row = <String, Object?>{};
      for (final key in keys) {
        final value = entry[key];
        if (key != 'sha256' && value != null && (key == 'sort' ? value is! int : value is! String)) {
          throw FormatException('内容字段 $key 类型错误');
        }
        row[key] = value;
      }
      final hash = entry['sha256'];
      if (hash == null || (hash is String && hash.trim().isEmpty)) {
        row['sha256'] = null;
      } else if (hash is String && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
        row['sha256'] = hash.toLowerCase();
      } else {
        row['sha256'] = null;
        invalidHashes.add(id);
      }
      // The server catalog is not an installed textbook. Persist only on install.
      rows[id] = row;
    }
    _publishedTextbooks = rows;
    _invalidPublishedTextbookHashes = invalidHashes;
    hasPublishedCatalog = true;
    return rows.values.toList();
  }

  Future<RowData> _descriptor(RowData textbook) async {
    final id = textOf(textbook, 'id');
    final file = textbook['resource_file'];
    if (file is! String || !file.endsWith('.zip')) {
      throw const FormatException('内容 resource_file 必须是 ZIP 文件名');
    }
    safeName(file);
    if (file.contains(RegExp(r'[%?#]'))) throw const FormatException('资源文件名不能含 URL 转义或查询字符');
    final folder = file.substring(0, file.length - 4);
    safeName(folder);
    final row = <String, Object?>{
      'textbook_id': id, 'folder': folder, 'file': file,
      'url': ResourceConfig.base.resolveUri(Uri(path: file)).toString(),
      // The hash is an update hint only; size comes from the HTTP response.
      'size': null, 'sha256': textbook['sha256'], 'update_time': nowMs(),
    };
    return row;
  }

  Future<void> remove(String id) async {
    if (activeBook != null) throw StateError('请等待当前内容任务完成');
    activeBook = id;
    report('delete', null, '正在删除学习资源');
    final playback = IosLessonPlayback.instance;
    String? operationId;
    bool committed = false;
    bool blockedHere = false;
    try {
      operationId = await _beginOperation(id, 'delete');
      await _recoverBook(id);
      final installed = await installation(id);
      final descriptors = await store.db.query('yzc_resource',
        columns: ['folder'], where: 'textbook_id=?', whereArgs: [id], limit: 1);
      final folder = textOf(installed ?? (descriptors.isEmpty ? const <String, Object?>{} : descriptors.single), 'folder');
      if (folder.isNotEmpty) {
        safeName(folder);
        await store.write(() => store.db.update('yzc_resource_operation', {
          'folder': folder, 'update_time': nowMs(),
        }, where: 'id=?', whereArgs: [operationId]));
      }
      unavailable.add(id);
      blockedHere = true;
      await playback.blockBook(id);
      await store.write(() => store.db.transaction((tx) async {
        for (final table in textbookContentTables.reversed) {
          await tx.delete(table, where: 'textbook_id=?', whereArgs: [id]);
        }
        await tx.delete('yzc_resource_install', where: 'textbook_id=?', whereArgs: [id]);
        await tx.delete('yzc_resource', where: 'textbook_id=?', whereArgs: [id]);
        await tx.delete('yzc_textbook', where: 'id=?', whereArgs: [id]);
        await tx.update('yzc_resource_operation', {'phase': 'db_committed', 'update_time': nowMs()}, where: 'id=?', whereArgs: [operationId]);
      }));
      committed = true;
      await _finishDelete({'id': operationId, 'textbook_id': id, 'folder': folder});
      report('delete', 1, '学习资源已删除');
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'textbook', operation: '删除内容', context: {'textbook_id': id, 'operation_id': operationId, 'stage': stage});
      if (operationId != null) {
        if (committed) {
          await store.write(() => store.db.update('yzc_resource_operation', {
            'error': e.toString(), 'update_time': nowMs(),
          }, where: 'id=?', whereArgs: [operationId]));
        } else {
          await _failOperation(operationId, e);
        }
      }
      rethrow;
    } finally {
      try {
        if (!committed && blockedHere) unavailable.remove(id);
        if (!unavailable.contains(id)) await playback.unblockBook(id);
      } finally { activeBook = null; notifyListeners(); }
    }
  }

  Future<void> _finishDelete(RowData operation) async {
    final id = textOf(operation, 'textbook_id'), folder = textOf(operation, 'folder');
    if (folder.isNotEmpty) {
      safeName(folder);
      final directory = Directory('${store.root.path}/resources/$folder');
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    await store.write(() => store.db.update('yzc_resource_operation', {
      'status': 'success', 'phase': 'done', 'error': null,
      'update_time': nowMs(), 'finish_time': nowMs(),
    }, where: 'id=?', whereArgs: [operation['id']]));
    unavailable.remove(id);
  }

  Future<void> _recoverBook(String id) async {
    final deletions = await store.db.query('yzc_resource_operation',
      where: 'textbook_id=? AND action=? AND status=? AND phase=?',
      whereArgs: [id, 'delete', 'running', 'db_committed'], orderBy: 'create_time,id');
    for (final operation in deletions) { await _finishDelete(operation); }
    final pending = await store.db.query('yzc_resource_job', where: 'textbook_id=? AND phase NOT IN (?,?)', whereArgs: [id, 'done', 'failed'], orderBy: 'create_time');
    for (final job in pending) {
      try { await _recoverJob(job); }
      catch (cleanupError, cleanupStack) {
        SystemErrors.record(cleanupError, cleanupStack, module: 'textbook', operation: '内容恢复与清理', context: {'textbook_id': activeBook, 'stage': stage});
        await _markBroken(job); rethrow;
      }
      final current = (await store.db.query('yzc_resource_job', columns: ['phase'], where: 'id=?', whereArgs: [job['id']])).single;
      if (!['done', 'failed'].contains(current['phase'])) throw StateError('上次内容任务尚未清理完成，请重试');
    }
  }

  Future<void> download(String id) async {
    if (activeBook != null) throw StateError('请等待当前内容任务完成');
    activeBook = id; report('catalog', null, '获取内容信息');
    RowData? job;
    Database? source;
    String? operationId;
    String? previousFolder;
    final blockedBooks = <String>{};
    final displacedBooks = <String>{};
    bool committed = false;
    final diagnostics = <String, Object?>{'textbook_id': id, 'base_url': ResourceConfig.baseUrl};
    try {
      final jobId = await _beginOperation(id, 'download');
      operationId = jobId;
      await _recoverBook(id);
      // Refresh availability without overwriting the installed textbook or its hash.
      final books = await refreshTextbooks();
      if (!books.any((b) => b['id'] == id && b['sfky'] == '1') || hasInvalidPublishedTextbookHash(id)) {
        throw StateError('本次目录中内容不存在或不可下载');
      }
      final remoteBook = books.firstWhere((book) => book['id'] == id);
      final descriptor = await _descriptor(remoteBook);
      diagnostics.addAll({'url': descriptor['url'], 'folder': descriptor['folder'], 'catalog_sha256': remoteBook['sha256']});
      await store.write(() => store.db.update('yzc_resource_operation', {
        'folder': descriptor['folder'], 'update_time': nowMs(),
      }, where: 'id=?', whereArgs: [operationId]));
      final old = await installation(id);
      previousFolder = old == null ? null : textOf(old, 'folder');
      final folder = textOf(descriptor, 'folder');
      final staging = '${store.root.path}/staging/$jobId';
      final backup = '${store.root.path}/backups/$jobId/$folder/mp3';
      final newJob = {'id': jobId, 'textbook_id': id, 'folder': folder, 'phase': 'download', 'staging': staging, 'backup': backup, 'audio_ready': 0, 'had_audio': 0, 'create_time': nowMs(), 'update_time': nowMs()};
      await store.write(() => store.db.insert('yzc_resource_job', newJob));
      job = newJob;
      await Directory(staging).create(recursive: true);
      await _excludeDownloadsFromBackup();
      final zip = File('$staging/$folder.zip');
      await _downloadFile(descriptor, zip);
      // Keep the actual ZIP hash in the operation log for later update checks.
      final hash = (await sha256.bind(zip.openRead()).first).toString();
      diagnostics['actual_sha256'] = hash;
      diagnostics['zip_path'] = zip.path;
      diagnostics['downloaded_bytes'] = await zip.length();
      report('extract', 0);
      await _extract(zip.path, '$staging/extracted', folder);
      final sourceDatabase = await openDatabase('$staging/extracted/$folder/data.sqlite', readOnly: true, singleInstance: false);
      source = sourceDatabase;
      final List<String> tables;
      try {
        tables = await _validate(sourceDatabase, id, '$staging/extracted/$folder');
      } on FormatException catch (e, stack) {
        SystemErrors.record(e, stack, module: 'textbook', operation: '校验内容数据', context: {...diagnostics, 'operation_id': operationId, 'stage': 'validate'});
        rethrow;
      }
      final installedConflicts = await store.db.query('yzc_resource_install',
        columns: ['textbook_id'], where: 'folder=? AND textbook_id<>?', whereArgs: [folder, id]);
      displacedBooks.addAll(installedConflicts.map((row) => textOf(row, 'textbook_id')).where((value) => value.isNotEmpty));
      final previousDescriptors = await store.db.query('yzc_resource',
        columns: ['id'], where: 'textbook_id=?', whereArgs: [id], orderBy: 'update_time DESC,id', limit: 1);
      descriptor['id'] = previousDescriptors.isEmpty ? store.newId() : previousDescriptors.single['id'];
      await _phase(jobId, 'prepared');
      final playback = IosLessonPlayback.instance;
      for (final book in {id, ...displacedBooks}) {
        unavailable.add(book);
        await playback.blockBook(book);
        blockedBooks.add(book);
      }
      // Reserve the write queue from filesystem preparation through commit.
      await store.write(() async {
        final targetPath = '${store.root.path}/resources/$folder/mp3';
        final hadAudio = await _resourceEntityExists(targetPath);
        await store.db.update('yzc_resource_job', {'phase': 'moving_audio', 'had_audio': hadAudio ? 1 : 0, 'update_time': nowMs()}, where: 'id=?', whereArgs: [jobId]);
        if (hadAudio) {
          await Directory(backup).parent.create(recursive: true);
          await _moveResourceEntity(targetPath, backup);
          await _excludeDownloadsFromBackup();
        }
        await _copyAudio(Directory('$staging/extracted/$folder/mp3'), Directory(targetPath));
        await store.db.update('yzc_resource_job', {'phase': 'audio_ready', 'audio_ready': 1, 'update_time': nowMs()}, where: 'id=?', whereArgs: [jobId]);
        final input = sourceDatabase;
        final counts = <String, int>{};
        for (final table in tables) { counts[table] = Sqflite.firstIntValue(await input.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0; }
        final total = counts.values.fold<int>(0, (a, b) => a + b); var inserted = 0;
        await store.db.transaction((tx) async {
          for (final displaced in displacedBooks) {
            for (final table in textbookContentTables.reversed) {
              await tx.delete(table, where: 'textbook_id=?', whereArgs: [displaced]);
            }
            await tx.delete('yzc_resource_install', where: 'textbook_id=?', whereArgs: [displaced]);
            await tx.delete('yzc_resource', where: 'textbook_id=?', whereArgs: [displaced]);
            await tx.delete('yzc_textbook', where: 'id=?', whereArgs: [displaced]);
          }
          // Replace this book's content using the current textbook schema.
          for (final table in textbookContentTables.reversed) {
            await tx.delete(table, where: 'textbook_id=?', whereArgs: [id]);
          }
          final book = Map<String, Object?>.from((await input.query('yzc_textbook')).single)
            ..remove('resource_file')
            ..remove('sha256');
          final bookChanged = await tx.update('yzc_textbook', book, where: 'id=?', whereArgs: [id]);
          if (bookChanged == 0) await tx.insert('yzc_textbook', book);
          // The current server catalog is authoritative for every matching
          // textbook field. Keep only the installed textbook's primary key.
          final publishedBook = Map<String, Object?>.from(remoteBook)..remove('id');
          await tx.update('yzc_textbook', publishedBook, where: 'id=?', whereArgs: [id]);
          for (final table in tables) {
            final columns = (await tx.rawQuery('PRAGMA table_info($table)')).map((r) => r['name'] as String).toList();
            for (var offset = 0; offset < counts[table]!; offset += 200) {
              final rows = await input.query(table, columns: columns, orderBy: 'id', limit: 200, offset: offset);
              final batch = tx.batch();
              for (final row in rows) { batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.abort); }
              await batch.commit(noResult: true);
              inserted += rows.length;
              report('sync', .6 + .35 * (total == 0 ? 1 : inserted / total), '同步数据 $inserted/$total');
            }
          }
          final installed = {'id': old?['id'] ?? store.newId(), 'textbook_id': id, 'folder': folder, 'status': 'ready', 'job_id': jobId, 'install_time': nowMs()};
          final changed = await tx.update('yzc_resource_install', installed, where: 'textbook_id=?', whereArgs: [id]);
          if (changed == 0) await tx.insert('yzc_resource_install', installed);
          await tx.delete('yzc_resource', where: 'folder=? AND textbook_id<>?', whereArgs: [folder, id]);
          await tx.delete('yzc_resource', where: 'textbook_id=?', whereArgs: [id]);
          await tx.insert('yzc_resource', descriptor);
          await tx.update('yzc_resource_operation', {
            'sha256': hash, 'status': 'success', 'phase': 'installed', 'error': null,
            'update_time': nowMs(), 'finish_time': nowMs(),
          }, where: 'id=?', whereArgs: [jobId]);
          await tx.update('yzc_resource_job', {'phase': 'db_committed', 'update_time': nowMs()}, where: 'id=?', whereArgs: [jobId]);
        });
      });
      committed = true;
      await sourceDatabase.close(); source = null;
      unavailable.remove(id);
      await playback.unblockBook(id);
      blockedBooks.remove(id);
      try { await _cleanup(job); } catch (cleanupError, cleanupStack) {
        SystemErrors.record(cleanupError, cleanupStack, module: 'textbook', operation: '内容恢复与清理', context: {'textbook_id': activeBook, 'stage': stage});
        await _phase(jobId, 'cleanup_pending');
      }
      if (previousFolder != null && previousFolder!.isNotEmpty && previousFolder != folder) {
        try { await _deleteFolderIfUnused(previousFolder!); } catch (cleanupError, cleanupStack) {
          SystemErrors.record(cleanupError, cleanupStack, module: 'textbook', operation: '清理旧学习资源目录', context: {'textbook_id': id, 'folder': previousFolder});
        }
      }
      report('sync', 1, '安装完成');
    } catch (e, stack) {
      SystemErrors.record(e, stack, module: 'textbook', operation: '下载并安装内容', context: {...diagnostics, 'operation_id': operationId, 'stage': stage, 'detail': detail, 'job_id': job?['id']});
      try { await source?.close(); } catch (cleanupError, cleanupStack) {
        SystemErrors.record(cleanupError, cleanupStack, module: 'textbook', operation: '内容恢复与清理', context: {'textbook_id': activeBook, 'stage': stage});
      }
      source = null;
      if (operationId != null) await _failOperation(operationId, e);
      if (job != null) {
        try { await _recoverJob((await store.db.query('yzc_resource_job', where: 'id=?', whereArgs: [job['id']])).single); }
        catch (cleanupError, cleanupStack) {
          SystemErrors.record(cleanupError, cleanupStack, module: 'textbook', operation: '内容恢复与清理', context: {'textbook_id': activeBook, 'stage': stage});
          await _markBroken(job);
        }
      }
      if (!committed) {
        for (final book in blockedBooks) {
          unavailable.remove(book);
          await IosLessonPlayback.instance.unblockBook(book);
        }
      }
      rethrow;
    } finally {
      activeBook = null; notifyListeners();
    }
  }

  Future<void> _phase(String id, String phase) => store.write(() async {
    await store.db.update('yzc_resource_job', {'phase': phase, 'update_time': nowMs()}, where: 'id=?', whereArgs: [id]);
  });
  Future<void> _downloadFile(RowData descriptor, File file) async {
    report('download', null);
    const maxSize = 2 * 1024 * 1024 * 1024;
    const reserve = 128 * 1024 * 1024;
    final capacity = await const MethodChannel('yuzhichu/device').invokeMethod<int>('freeSpace');
    if (capacity != null && capacity < reserve) throw StateError('可用存储空间不足');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..autoUncompress = false;
    IOSink? sink;
    try {
      final uri = Uri.parse(textOf(descriptor, 'url')).replace(queryParameters: {'t': '${nowMs()}'});
      final request = await client.getUrl(uri).timeout(const Duration(seconds: 20));
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) throw HttpException('下载失败（${response.statusCode}）');
      final encoding = response.headers.value(HttpHeaders.contentEncodingHeader);
      if (encoding != null && encoding.toLowerCase() != 'identity') throw const FormatException('ZIP 下载响应编码不受支持');
      final expected = response.contentLength;
      if (expected > maxSize) throw StateError('ZIP 超过 2 GB 限制');
      if (expected == 0) throw const FormatException('下载文件为空');
      if (capacity != null && expected > 0 && capacity < expected * 3 + reserve) throw StateError('可用存储空间不足');
      sink = file.openWrite(); int received = 0;
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        received += chunk.length;
        if (received > maxSize) throw StateError('ZIP 超过 2 GB 限制');
        if (expected >= 0 && received > expected) throw const FormatException('下载文件超过 HTTP 声明长度');
        if (capacity != null && capacity < received * 3 + reserve) throw StateError('可用存储空间不足');
        sink.add(chunk);
        await sink.flush();
        report('download', expected > 0 ? received / expected : null,
          expected > 0 ? '$received / $expected 字节' : '已下载 $received 字节');
      }
      await sink.flush();
      if (received == 0) throw const FormatException('下载文件为空');
      if (expected >= 0 && received != expected) throw const FormatException('下载文件与 HTTP 声明长度不符');
    } finally { await sink?.close(); client.close(force: true); }
  }
  Future<void> _extract(String zip, String destination, String folder) async {
    final password = await ResourceConfig.restorePassword();
    final capacity = await const MethodChannel('yuzhichu/device').invokeMethod<int>('freeSpace');
    final messages = ReceivePort(), errors = ReceivePort(), exits = ReceivePort();
    final done = Completer<void>();
    final subscription = messages.listen((dynamic message) {
      final m = message as Map;
      if (m['progress'] is num) report('extract', (m['progress'] as num).toDouble());
      if (m['error'] != null && !done.isCompleted) done.completeError(StateError('解压失败：${m['error']}'), StackTrace.fromString(m['stack']?.toString() ?? '子进程未提供堆栈'));
      if (m['done'] == true && !done.isCompleted) done.complete();
    });
    final errorSubscription = errors.listen((dynamic e) { if (!done.isCompleted) done.completeError(StateError('解压进程失败：${e is List && e.isNotEmpty ? e.first : e}'), e is List && e.length > 1 ? StackTrace.fromString(e[1].toString()) : StackTrace.current); });
    final exitSubscription = exits.listen((_) { Future<void>.delayed(const Duration(milliseconds: 100), () { if (!done.isCompleted) done.completeError(StateError('解压进程意外退出')); }); });
    Isolate? worker;
    try {
      worker = await Isolate.spawn(extractResourceArchiveWorker, <Object>[messages.sendPort, zip, destination, folder, password, capacity ?? -1], onError: errors.sendPort, onExit: exits.sendPort);
      await done.future;
    } finally {
      worker?.kill(priority: Isolate.immediate);
      await subscription.cancel(); await errorSubscription.cancel(); await exitSubscription.cancel();
      messages.close(); errors.close(); exits.close();
    }
  }

  Future<List<String>> _validate(Database source, String id, String folder) async {
    final integrity = await source.rawQuery('PRAGMA quick_check');
    if (integrity.length != 1 || integrity.single.values.single != 'ok') throw const FormatException('内容 SQLite 损坏');
    final schema = await source.rawQuery("SELECT name,type FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'");
    final names = schema.where((r) => r['type'] == 'table').map((r) => textOf(r, 'name')).toSet();
    const tables = textbookContentTables;
    final allowed = {'yzc_textbook', ...tables};
    if (!names.containsAll(allowed)) throw const FormatException('内容数据库缺少必需数据表');
    if (schema.any((r) => !['table', 'index'].contains(r['type']) || (r['type'] == 'table' && !allowed.contains(r['name'])))) throw const FormatException('资源数据库含未约定结构');
    final sourceColumns = <String, List<RowData>>{};
    for (final table in ['yzc_textbook', ...tables]) {
      final actual = await source.rawQuery('PRAGMA table_info($table)');
      sourceColumns[table] = actual;
      final local = await store.db.rawQuery('PRAGMA table_info($table)');
      // Download metadata belongs to the app/server, and can be absent in old ZIPs.
      final metadata = table == 'yzc_textbook' ? {'resource_file', 'sha256'} : <String>{};
      final actualContent = actual.where((column) => !metadata.contains(column['name'])).toList();
      final localContent = local.where((column) => !metadata.contains(column['name'])).toList();
      if (actualContent.length != localContent.length) throw FormatException('$table 字段不符');
      for (var i = 0; i < localContent.length; i++) {
        for (final key in ['name', 'type', 'pk']) {
          if (actualContent[i][key].toString().toLowerCase() != localContent[i][key].toString().toLowerCase()) {
            throw FormatException('$table 的 ${localContent[i]['name']} 定义不符');
          }
        }
      }
    }
    final books = await source.query('yzc_textbook');
    if (books.length != 1 || books.single['id'] != id) throw const FormatException('包内内容 ID 不匹配');
    for (final table in tables) {
      final wrong = Sqflite.firstIntValue(await source.rawQuery('SELECT COUNT(*) FROM $table WHERE textbook_id IS NULL OR textbook_id<>? OR id IS NULL OR id=?', [id, ''])) ?? 0;
      if (wrong > 0) throw FormatException('$table 含其他内容或无效 ID');
      final columns = sourceColumns[table]!;
      // SQLite VARCHAR/INT affinity does not enforce value types by itself.
      for (var offset = 0; ; offset += 200) {
        final rows = await source.query(table, orderBy: 'id', limit: 200, offset: offset);
        for (final row in rows) {
          for (final column in columns) {
            final key = textOf(column, 'name'), type = textOf(column, 'type').toLowerCase();
            final value = row[key];
            if (value != null && (type.contains('int') ? value is! int : value is! String)) {
              throw FormatException('$table.$key 的数据类型不正确');
            }
          }
        }
        if (rows.length < 200) break;
      }
    }
    // Check logical relationships by fields; do not use database foreign keys.
    final relations = <List<String>>[
      ['yzc_lessons', 'unit_id', 'yzc_unit'],
      ['yzc_words', 'lessons_id', 'yzc_lessons'], ['yzc_content', 'lessons_id', 'yzc_lessons'],
      ['yzc_words', 'unit_id', 'yzc_unit'], ['yzc_content', 'unit_id', 'yzc_unit'],
      ['yzc_grammar', 'lessons_id', 'yzc_lessons'],
      ['yzc_ai_question', 'lessons_id', 'yzc_lessons'], ['yzc_ai_question', 'unit_id', 'yzc_unit'],
    ];
    for (final relation in relations) {
      final child = relation[0], column = relation[1], parent = relation[2];
      final required = column == 'lessons_id' || child == 'yzc_ai_question';
      final missing = Sqflite.firstIntValue(await source.rawQuery('SELECT COUNT(*) FROM $child c LEFT JOIN $parent p ON p.id=c.$column AND p.textbook_id=c.textbook_id WHERE ${required ? '' : 'c.$column IS NOT NULL AND '}p.id IS NULL')) ?? 0;
      if (missing > 0) throw FormatException('$child 的 $column 关联不完整');
    }
    for (final table in ['yzc_words', 'yzc_content']) {
      final names = await source.rawQuery('SELECT DISTINCT phonetic FROM $table WHERE phonetic IS NOT NULL AND phonetic<>?', ['']);
      for (final row in names) {
        final name = textOf(row, 'phonetic'); safeName(name);
        if (!name.toLowerCase().endsWith('.mp3') || !await File('$folder/mp3/$name').exists()) throw FormatException('缺少音频 $name');
      }
    }
    final invalid = await source.rawQuery('SELECT q.id FROM yzc_ai_question q JOIN yzc_lessons l ON l.id=q.lessons_id AND l.textbook_id=q.textbook_id WHERE q.unit_id<>l.unit_id OR l.unit_id IS NULL OR q.lesson<>l.lesson OR l.lesson IS NULL LIMIT 1');
    if (invalid.isNotEmpty) throw const FormatException('题目与课程、单元关联不一致');
    for (var offset = 0; ; offset += 200) {
      final questions = await source.query('yzc_ai_question', orderBy: 'id', limit: 200, offset: offset);
      for (final question in questions) {
        if (textOf(question, 'question').trim().isEmpty || !questionRelations.contains(question['relation'])) throw const FormatException('题目内容或分类无效');
        validateQuestionAnswerMode(question);
      }
      if (questions.length < 200) break;
    }
    for (final table in const ['yzc_words', 'yzc_content', 'yzc_grammar', 'yzc_ai_question']) {
      for (var offset = 0; ; offset += 200) {
        final rows = await source.query(table, orderBy: 'id', limit: 200, offset: offset);
        for (final row in rows) {
          final type = textOf(row, 'media_type');
          if (type.isEmpty || type == 'text') continue;
          final filename = textbookMediaFilename(textOf(row, 'media_src'), type);
          if (!await File('$folder/mp3/$filename').exists()) throw FormatException('$table 缺少媒体 $filename');
          final mediaConfig = textOf(row, 'media_config');
          if ((type == 'image' || type == 'audio' || type == 'video') && mediaConfig.trim().isNotEmpty) {
            throw FormatException('$table 普通媒体 ${row['id']} 不能包含互动配置');
          }
          if (type == 'interactive_image') {
            final config = CourseImageInteractionConfig.parse(mediaConfig);
            if (config == null) throw FormatException('$table 互动图片 ${row['id']} 缺少有效配置');
            for (final hotspot in config.hotspots) {
              if (!await File('$folder/mp3/${hotspot.audioSource}').exists()) {
                throw FormatException('$table 互动图片 ${row['id']} 缺少音频 ${hotspot.audioSource}');
              }
            }
          }
        }
        if (rows.length < 200) break;
      }
    }
    return tables;
  }
  Future<void> _copyAudio(Directory from, Directory to) async {
    final files = await from.list().where((f) => f is File).cast<File>().toList();
    int total = 0, copied = 0;
    for (final file in files) { total += await file.length(); }
    final capacity = await const MethodChannel('yuzhichu/device').invokeMethod<int>('freeSpace');
    if (capacity != null && capacity < total + 128 * 1024 * 1024) throw StateError('同步学习资源的空间不足');
    await to.create(recursive: true);
    await _excludeDownloadsFromBackup();
    for (final file in files) {
      final target = File('${to.path}/${file.uri.pathSegments.last}');
      final sink = target.openWrite();
      try {
        await for (final bytes in file.openRead()) {
          sink.add(bytes); copied += bytes.length;
          await sink.flush();
          report('sync', total == 0 ? .6 : .6 * copied / total, '复制学习资源 $copied/$total 字节');
        }
        await sink.flush();
      } finally { await sink.close(); }
    }
    report('sync', .6, '学习资源已就位');
  }
  Future<void> _excludeDownloadsFromBackup() async {
    if (Platform.isIOS) {
      await const MethodChannel('yuzhichu/device')
          .invokeMethod<void>('excludeDownloadedResourcesFromBackup');
    }
  }

  Future<void> recover() async {
    try {
      await _excludeDownloadsFromBackup();
    } catch (e, stack) {
      // A backup attribute failure must not block existing offline learning.
      SystemErrors.record(e, stack, module: 'textbook', operation: '设置资源备份属性');
    }
    final jobs = await store.db.query('yzc_resource_job', where: 'phase NOT IN (?,?)', whereArgs: ['done', 'failed'], orderBy: 'create_time');
    for (final job in jobs) {
      try { await _recoverJob(job); } catch (cleanupError, cleanupStack) {
        SystemErrors.record(cleanupError, cleanupStack, module: 'textbook', operation: '内容恢复与清理', context: {'textbook_id': activeBook, 'stage': stage});
        await _markBroken(job);
      }
    }
    final operations = await store.db.query('yzc_resource_operation', where: 'status=?', whereArgs: ['running'], orderBy: 'create_time,id');
    for (final operation in operations) {
      if (operation['action'] == 'delete' && operation['phase'] == 'db_committed') {
        final id = textOf(operation, 'textbook_id');
        try {
          await _finishDelete(operation);
          await IosLessonPlayback.instance.unblockBook(id);
        } catch (e, stack) {
          SystemErrors.record(e, stack, module: 'textbook', operation: '恢复内容删除', context: {'textbook_id': id, 'operation_id': operation['id']});
          unavailable.add(id);
          await store.write(() => store.db.update('yzc_resource_operation', {
            'error': e.toString(), 'update_time': nowMs(),
          }, where: 'id=?', whereArgs: [operation['id']]));
          await IosLessonPlayback.instance.blockBook(id);
        }
      } else {
        await _failOperation(textOf(operation, 'id'), '操作因应用退出而中断，未完成安装或删除');
      }
    }
    // A system backup retains learning data, but deliberately omits media.
    for (final row in await installations()) {
      if (row['status'] != 'ready') continue;
      final folder = textOf(row, 'folder');
      safeName(folder);
      if (!await Directory('${store.root.path}/resources/$folder/mp3').exists()) {
        final id = textOf(row, 'textbook_id');
        await store.write(() => store.db.update('yzc_resource_install',
          {'status': 'broken'}, where: 'textbook_id=?', whereArgs: [id]));
        unavailable.add(id);
        await IosLessonPlayback.instance.blockBook(id);
      }
    }
  }
  Future<void> _recoverJob(RowData job) async {
    final id = textOf(job, 'textbook_id'), folder = textOf(job, 'folder'); safeName(folder);
    final installed = await installation(id);
    if (installed?['job_id'] == job['id']) {
      final target = Directory('${store.root.path}/resources/$folder/mp3');
      if (!await target.exists()) { unavailable.add(id); throw StateError('新版音频丢失，请重新下载'); }
      try { await _cleanup(job); } catch (cleanupError, cleanupStack) {
        SystemErrors.record(cleanupError, cleanupStack, module: 'textbook', operation: '内容恢复与清理', context: {'textbook_id': activeBook, 'stage': stage});
        await _phase(textOf(job, 'id'), 'cleanup_pending');
      }
      unavailable.remove(id);
      await IosLessonPlayback.instance.unblockBook(id); return;
    }
    final phase = textOf(job, 'phase');
    if (!['download', 'prepared'].contains(phase)) {
      final targetPath = '${store.root.path}/resources/$folder/mp3';
      final backupPath = textOf(job, 'backup');
      if (await _resourceEntityExists(backupPath)) {
        // Persist rollback intent before changing files. If we crash after
        // rename, the surviving target is already the restored old directory.
        await _phase(textOf(job, 'id'), 'rolling_back');
        if (await _resourceEntityExists(targetPath)) await _deleteResourceEntity(targetPath);
        await _moveResourceEntity(backupPath, targetPath);
        await _excludeDownloadsFromBackup();
      } else if (intOf(job, 'had_audio') == 0) {
        if (await _resourceEntityExists(targetPath)) await _deleteResourceEntity(targetPath);
      } else if (!['moving_audio', 'rolling_back'].contains(phase) || !await _resourceEntityExists(targetPath)) {
        unavailable.add(id); throw StateError('旧音频备份缺失，需重新下载');
      }
    }
    final staging = Directory(textOf(job, 'staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await _failOperation(textOf(job, 'id'), '安装中断，已恢复原内容状态');
    await _phase(textOf(job, 'id'), 'failed'); unavailable.remove(id);
    if (installed?['status'] == 'broken') unavailable.add(id);
    await IosLessonPlayback.instance.unblockBook(id);
  }
  Future<void> _markBroken(RowData job) async {
    final id = textOf(job, 'textbook_id');
    unavailable.add(id);
    await store.write(() => store.db.transaction((tx) async {
      await tx.update('yzc_resource_install', {'status': 'broken'}, where: 'textbook_id=?', whereArgs: [id]);
      await tx.update('yzc_resource_job', {'phase': 'failed', 'error': '恢复失败，等待重新下载', 'update_time': nowMs()}, where: 'id=?', whereArgs: [job['id']]);
      await tx.update('yzc_resource_operation', {
        'status': 'failed', 'error': '恢复失败，等待重新下载', 'update_time': nowMs(), 'finish_time': nowMs(),
      }, where: 'id=? AND status=?', whereArgs: [job['id'], 'running']);
    }));
    await IosLessonPlayback.instance.blockBook(id);
  }
  Future<void> _cleanup(RowData job) async {
    for (final path in [textOf(job, 'backup'), textOf(job, 'staging')]) {
      if (await _resourceEntityExists(path)) await _deleteResourceEntity(path);
    }
    await _phase(textOf(job, 'id'), 'done');
  }

  Future<void> _deleteFolderIfUnused(String folder) async {
    safeName(folder);
    final references = await store.db.query('yzc_resource_install',
      columns: ['id'], where: 'folder=?', whereArgs: [folder], limit: 1);
    if (references.isNotEmpty) return;
    final path = '${store.root.path}/resources/$folder';
    if (await _resourceEntityExists(path)) await _deleteResourceEntity(path);
  }
}
