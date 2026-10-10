import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import 'config.dart';
import 'data.dart';
import 'ios_lesson_playback.dart';
import 'ai_question.dart';
import 'resource_transfer.dart';
import 'user_error.dart';
import 'system_errors.dart';
import 'course/feature/image_interaction_config.dart';

const textbookContentTables = [
  'yzc_unit',
  'yzc_lessons',
  'yzc_words',
  'yzc_content',
  'yzc_grammar',
  'yzc_ai_question',
];
const optionalTextbookContentColumns = {
  'media_type',
  'media_src',
  'media_config',
};

class ResourceContentIssue {
  const ResourceContentIssue(
    this.location,
    this.message, {
    this.skipped = false,
  });
  final String location, message;
  final bool skipped;
  @override
  String toString() => '$location：$message';
}

class TextbookValidationResult {
  const TextbookValidationResult({
    required this.tables,
    required this.normal,
    required this.issues,
    required this.skippedRows,
  });
  final List<String> tables;
  final int normal;
  final List<ResourceContentIssue> issues;
  final Map<String, Set<String>> skippedRows;
  int get skipped => issues.where((issue) => issue.skipped).length;
  int get degraded => issues.length - skipped;
  String get summary => '正常 $normal，跳过 $skipped，降级 $degraded';
}

bool shouldImportResourceRow(
  TextbookValidationResult validation,
  String table,
  RowData row,
) => validation.skippedRows[table]?.contains(textOf(row, 'id')) != true;

/// Projects one source row onto the installed schema without mutating the
/// package database. Old packages may omit media columns, while some SQLite
/// producers explicitly store NULL or blanks despite the app's NOT NULL
/// media_type contract.
RowData normalizeResourceRowForImport(
  RowData sourceRow,
  Set<String> localColumns,
) {
  final row = Map<String, Object?>.from(sourceRow);
  if (localColumns.contains('media_type') &&
      textOf(row, 'media_type').trim().isEmpty) {
    row['media_type'] = 'text';
  }
  if (localColumns.contains('media_src'))
    row.putIfAbsent('media_src', () => null);
  if (localColumns.contains('media_config'))
    row.putIfAbsent('media_config', () => null);
  return row;
}

void safeName(String name) {
  if (name.isEmpty ||
      name == '.' ||
      name == '..' ||
      name.contains('/') ||
      name.contains('\\') ||
      name.contains(':') ||
      name.contains('\u0000') ||
      name.startsWith('.'))
    throw const FormatException('资源文件名无效');
}

Future<bool> _resourceEntityExists(String path) async =>
    await FileSystemEntity.type(path, followLinks: false) !=
    FileSystemEntityType.notFound;

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
  if (type == FileSystemEntityType.notFound)
    throw FileSystemException('资源路径不存在', source);
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
  if (parts.length != 2 || parts.first != 'mp3')
    throw const FormatException('内容媒体必须位于 mp3 文件夹');
  final filename = parts.last;
  safeName(filename);
  final extension = filename.split('.').last.toLowerCase();
  final allowed = switch (type) {
    'image' || 'interactive_image' => {'png', 'jpg', 'jpeg', 'webp'},
    'video' => {'mp4'},
    'audio' => {'mp3'},
    _ => <String>{},
  };
  if (!allowed.contains(extension))
    throw const FormatException('内容媒体类型或格式不受支持');
  return filename;
}

class Resources extends ChangeNotifier {
  Resources(
    this.store, {
    ResourceTransfer? transfer,
    Uri? base,
    Future<String> Function()? password,
    this.onCheckpoint,
  }) : transfer = transfer ?? ResourceTransfer(),
       _base = base,
       _password = password;
  final ResourceTransfer transfer;
  final Uri? _base;
  final Future<String> Function()? _password;
  @visibleForTesting
  final Future<void> Function(String point)? onCheckpoint;
  ResourceTask? _task;
  bool get canCancel => _task?.canCancel == true;
  bool get cancelling => _task?.cancelled == true;
  void cancelDownload() {
    if (!canCancel) return;
    _task!.cancel();
    report('cancel', null, '正在取消并恢复原内容');
  }

  Future<void> _checkpoint(String point) async {
    await onCheckpoint?.call(point);
    _task?.check();
  }

  final AppStore store;
  String? activeBook;
  String? lastInstallSummary;
  String? lastError, lastFailedBook;
  bool lastCancelled = false;
  String stage = '', detail = '';
  double? progress;
  final Set<String> unavailable = {};
  Map<String, RowData> _publishedTextbooks = {};
  Set<String> _invalidPublishedTextbookHashes = {};
  bool hasPublishedCatalog = false;
  List<RowData> get publishedTextbooks => _publishedTextbooks.values.toList();
  RowData? publishedTextbook(String id) => _publishedTextbooks[id];
  bool hasInvalidPublishedTextbookHash(String id) =>
      _invalidPublishedTextbookHashes.contains(id);
  void clearPublishedTextbooks() {
    _publishedTextbooks = {};
    _invalidPublishedTextbookHashes = {};
    hasPublishedCatalog = false;
  }

  DateTime _lastNotice = DateTime.fromMillisecondsSinceEpoch(0);
  void report(String next, double? value, [String message = '']) {
    final changed = next != stage;
    stage = next;
    progress = value;
    detail = message;
    if (changed ||
        value == 1 ||
        DateTime.now().difference(_lastNotice).inMilliseconds > 80) {
      _lastNotice = DateTime.now();
      notifyListeners();
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
    await store.write(
      () => store.db.insert('yzc_resource_operation', {
        'id': id,
        'textbook_id': book,
        'action': action,
        'status': 'running',
        'phase': 'started',
        'create_time': time,
        'update_time': time,
      }),
    );
    return id;
  }

  Future<void> _failOperation(String id, Object error) => store.write(() async {
    final time = nowMs();
    await store.db.update(
      'yzc_resource_operation',
      {
        'status': 'failed',
        'error': error.toString(),
        'update_time': time,
        'finish_time': time,
      },
      where: 'id=? AND status=?',
      whereArgs: [id, 'running'],
    );
  });
  Future<String> audioPath(String book, String filename) async {
    safeName(filename);
    if (unavailable.contains(book)) throw StateError('内容正在同步或需要修复');
    final row = await installation(book);
    if (row == null || row['status'] != 'ready') throw StateError('请先下载内容');
    final folder = textOf(row, 'folder');
    safeName(folder);
    final path = '${store.root.path}/resources/$folder/mp3/$filename';
    if (!await File(path).exists()) throw StateError('音频文件缺失，请重新下载内容');
    return path;
  }

  Future<bool> hasAudio(String book, String filename) async {
    try {
      await audioPath(book, filename);
      return true;
    } on Object {
      return false;
    }
  }

  Future<String> mediaPath(String book, String source, String type) async {
    final filename = textbookMediaFilename(source, type);
    if (unavailable.contains(book)) throw StateError('内容正在同步或需要修复');
    final row = await installation(book);
    if (row == null || row['status'] != 'ready') throw StateError('请先下载内容');
    final folder = textOf(row, 'folder');
    safeName(folder);
    final root = Directory('${store.root.path}/resources/$folder/mp3');
    final file = File('${root.path}/$filename');
    if (!await file.exists()) throw StateError('媒体文件缺失，请重新下载内容');
    final rootPath = await root.resolveSymbolicLinks();
    final path = await file.resolveSymbolicLinks();
    if (File(path).parent.path != rootPath)
      throw const FormatException('内容媒体路径无效');
    return path;
  }

  Future<Object?> _json(String name) => transfer.json(
    (_base ?? ResourceConfig.base).resolve(name),
    task: _task,
    report: (stage, value, detail) => report(stage, value, detail),
  );
  Future<List<RowData>> refreshTextbooks() async {
    final json = await _json('yzc_textbook.json');
    if (json is! List) throw const FormatException('内容目录必须是数组');
    final columns = await store.db.rawQuery('PRAGMA table_info(yzc_textbook)');
    final keys = columns.map((r) => r['name'] as String).toSet();
    final rows = <String, RowData>{};
    final invalidHashes = <String>{};
    for (final entry in json) {
      if (entry is! Map ||
          entry['id'] is! String ||
          (entry['id'] as String).isEmpty ||
          rows.containsKey(entry['id'])) {
        throw const FormatException('内容 ID 必须为唯一字符串');
      }
      final id = entry['id'] as String;
      final row = <String, Object?>{};
      for (final key in keys) {
        final value = entry[key];
        if (key != 'sha256' &&
            value != null &&
            (key == 'sort' ? value is! int : value is! String)) {
          throw FormatException('内容字段 $key 类型错误');
        }
        row[key] = value;
      }
      final hash = entry['sha256'];
      if (hash == null || (hash is String && hash.trim().isEmpty)) {
        row['sha256'] = null;
      } else if (hash is String &&
          RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hash)) {
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
    if (file.contains(RegExp(r'[%?#]')))
      throw const FormatException('资源文件名不能含 URL 转义或查询字符');
    final folder = file.substring(0, file.length - 4);
    safeName(folder);
    final row = <String, Object?>{
      'textbook_id': id, 'folder': folder, 'file': file,
      'url': (_base ?? ResourceConfig.base)
          .resolveUri(Uri(path: file))
          .toString(),
      // Missing hashes remain compatible; a supplied digest must match the ZIP.
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
      final descriptors = await store.db.query(
        'yzc_resource',
        columns: ['folder'],
        where: 'textbook_id=?',
        whereArgs: [id],
        limit: 1,
      );
      final folder = textOf(
        installed ??
            (descriptors.isEmpty
                ? const <String, Object?>{}
                : descriptors.single),
        'folder',
      );
      if (folder.isNotEmpty) {
        safeName(folder);
        await store.write(
          () => store.db.update(
            'yzc_resource_operation',
            {'folder': folder, 'update_time': nowMs()},
            where: 'id=?',
            whereArgs: [operationId],
          ),
        );
      }
      unavailable.add(id);
      blockedHere = true;
      await playback.blockBook(id).timeout(const Duration(seconds: 5));
      await store.write(
        () => store.db.transaction((tx) async {
          for (final table in textbookContentTables.reversed) {
            await tx.delete(table, where: 'textbook_id=?', whereArgs: [id]);
          }
          await tx.delete(
            'yzc_resource_install',
            where: 'textbook_id=?',
            whereArgs: [id],
          );
          await tx.delete(
            'yzc_resource',
            where: 'textbook_id=?',
            whereArgs: [id],
          );
          await tx.delete('yzc_textbook', where: 'id=?', whereArgs: [id]);
          await tx.update(
            'yzc_resource_operation',
            {'phase': 'db_committed', 'update_time': nowMs()},
            where: 'id=?',
            whereArgs: [operationId],
          );
        }),
      );
      committed = true;
      await _finishDelete({
        'id': operationId,
        'textbook_id': id,
        'folder': folder,
      });
      report('delete', 1, '学习资源已删除');
    } catch (e, stack) {
      SystemErrors.record(
        e,
        stack,
        module: 'textbook',
        operation: '删除内容',
        context: {
          'textbook_id': id,
          'operation_id': operationId,
          'stage': stage,
        },
      );
      if (operationId != null) {
        if (committed) {
          await store.write(
            () => store.db.update(
              'yzc_resource_operation',
              {'error': e.toString(), 'update_time': nowMs()},
              where: 'id=?',
              whereArgs: [operationId],
            ),
          );
        } else {
          await _failOperation(operationId, e);
        }
      }
      rethrow;
    } finally {
      try {
        if (!committed && blockedHere) unavailable.remove(id);
        if (!unavailable.contains(id))
          await playback.unblockBook(id).timeout(const Duration(seconds: 5));
      } finally {
        activeBook = null;
        notifyListeners();
      }
    }
  }

  Future<void> _finishDelete(RowData operation) async {
    final id = textOf(operation, 'textbook_id'),
        folder = textOf(operation, 'folder');
    if (folder.isNotEmpty) {
      safeName(folder);
      final directory = Directory('${store.root.path}/resources/$folder');
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    await store.write(
      () => store.db.update(
        'yzc_resource_operation',
        {
          'status': 'success',
          'phase': 'done',
          'error': null,
          'update_time': nowMs(),
          'finish_time': nowMs(),
        },
        where: 'id=?',
        whereArgs: [operation['id']],
      ),
    );
    unavailable.remove(id);
  }

  Future<void> _recoverBook(String id) async {
    await _cleanFailedStaging(id: id);
    final deletions = await store.db.query(
      'yzc_resource_operation',
      where: 'textbook_id=? AND action=? AND status=? AND phase=?',
      whereArgs: [id, 'delete', 'running', 'db_committed'],
      orderBy: 'create_time,id',
    );
    for (final operation in deletions) {
      await _finishDelete(operation);
    }
    final pending = await store.db.query(
      'yzc_resource_job',
      where: 'textbook_id=? AND phase NOT IN (?,?)',
      whereArgs: [id, 'done', 'failed'],
      orderBy: 'create_time',
    );
    for (final job in pending) {
      try {
        await _recoverJob(job);
      } catch (cleanupError, cleanupStack) {
        SystemErrors.record(
          cleanupError,
          cleanupStack,
          module: 'textbook',
          operation: '内容恢复与清理',
          context: {'textbook_id': activeBook, 'stage': stage},
        );
        await _markBroken(job);
        final state = await store.db.query(
          'yzc_resource_job',
          columns: ['phase'],
          where: 'id=?',
          whereArgs: [job['id']],
        );
        if (state.isEmpty || state.single['phase'] != 'failed') rethrow;
      }
      final current = (await store.db.query(
        'yzc_resource_job',
        columns: ['phase'],
        where: 'id=?',
        whereArgs: [job['id']],
      )).single;
      if (!['done', 'failed', 'cleanup_pending'].contains(current['phase']))
        throw StateError('上次内容任务尚未恢复完成，请重试');
    }
  }

  Future<void> download(String id) async {
    if (activeBook != null) throw StateError('请等待当前内容任务完成');
    final task = ResourceTask();
    _task = task;
    lastInstallSummary = null;
    lastError = null;
    lastFailedBook = null;
    lastCancelled = false;
    activeBook = id;
    report('catalog', null, '获取内容信息');
    RowData? job;
    Database? source;
    String? operationId;
    String? previousFolder;
    final blockedBooks = <String>{};
    final displacedBooks = <String>{};
    bool committed = false;
    final diagnostics = <String, Object?>{
      'textbook_id': id,
      'base_url': ResourceConfig.baseUrl,
    };
    try {
      final jobId = await _beginOperation(id, 'download');
      operationId = jobId;
      await _recoverBook(id);
      // Refresh availability without overwriting the installed textbook or its hash.
      final books = await refreshTextbooks();
      if (!books.any((b) => b['id'] == id && b['sfky'] == '1') ||
          hasInvalidPublishedTextbookHash(id)) {
        throw StateError('本次目录中内容不存在或不可下载');
      }
      await _checkpoint('catalog');
      final remoteBook = books.firstWhere((book) => book['id'] == id);
      final descriptor = await _descriptor(remoteBook);
      diagnostics.addAll({
        'url': descriptor['url'],
        'folder': descriptor['folder'],
        'catalog_sha256': remoteBook['sha256'],
      });
      await store.write(
        () => store.db.update(
          'yzc_resource_operation',
          {'folder': descriptor['folder'], 'update_time': nowMs()},
          where: 'id=?',
          whereArgs: [operationId],
        ),
      );
      final old = await installation(id);
      previousFolder = old == null ? null : textOf(old, 'folder');
      final folder = textOf(descriptor, 'folder');
      final staging = '${store.root.path}/staging/$jobId';
      final backup = '${store.root.path}/backups/$jobId/$folder/mp3';
      final newJob = {
        'id': jobId,
        'textbook_id': id,
        'folder': folder,
        'phase': 'download',
        'staging': staging,
        'backup': backup,
        'audio_ready': 0,
        'had_audio': 0,
        'create_time': nowMs(),
        'update_time': nowMs(),
      };
      await store.write(() => store.db.insert('yzc_resource_job', newJob));
      job = newJob;
      await Directory(staging).create(recursive: true);
      await _excludeDownloadsFromBackup();
      final zip = File('$staging/$folder.zip');
      final hash = await transfer.download(
        Uri.parse(textOf(descriptor, 'url')),
        zip,
        task,
        (stage, value, detail) => report(stage, value, detail),
        expectedHash: descriptor['sha256'] as String?,
      );
      await _checkpoint('download');
      diagnostics['actual_sha256'] = hash;
      diagnostics['zip_path'] = zip.path;
      diagnostics['downloaded_bytes'] = await zip.length();
      report('extract', 0);
      await _extract(zip.path, '$staging/extracted', folder);
      await _checkpoint('extract');
      report('validate', null, '正在校验教材数据');
      final sourceDatabase = await openDatabase(
        '$staging/extracted/$folder/data.sqlite',
        readOnly: true,
        singleInstance: false,
      );
      source = sourceDatabase;
      final TextbookValidationResult validation;
      try {
        validation = await _validate(
          sourceDatabase,
          id,
          '$staging/extracted/$folder',
        );
      } on FormatException catch (e, stack) {
        SystemErrors.record(
          e,
          stack,
          module: 'textbook',
          operation: '校验内容数据',
          context: {
            ...diagnostics,
            'operation_id': operationId,
            'stage': 'validate',
          },
        );
        rethrow;
      }
      await _checkpoint('validated');
      final tables = validation.tables;
      lastInstallSummary = validation.issues.isEmpty
          ? null
          : validation.summary;
      diagnostics.addAll({
        'content_normal': validation.normal,
        'content_skipped': validation.skipped,
        'content_degraded': validation.degraded,
      });
      if (validation.issues.isNotEmpty) {
        SystemErrors.record(
          FormatException(validation.issues.join('\n')),
          StackTrace.current,
          module: 'textbook',
          operation: '内容兼容性降级',
          severity: 'warning',
          hint: '内容已安装，部分题目或媒体已降级',
          context: {
            'textbook_id': id,
            'operation_id': operationId,
            'summary': validation.summary,
          },
        );
      }
      final installedConflicts = await store.db.query(
        'yzc_resource_install',
        columns: ['textbook_id'],
        where: 'folder=? AND textbook_id<>?',
        whereArgs: [folder, id],
      );
      if (installedConflicts.isNotEmpty) {
        throw const FormatException('资源目录与其他已安装教材冲突，原教材已保留');
      }
      final previousDescriptors = await store.db.query(
        'yzc_resource',
        columns: ['id'],
        where: 'textbook_id=?',
        whereArgs: [id],
        orderBy: 'update_time DESC,id',
        limit: 1,
      );
      descriptor['id'] = previousDescriptors.isEmpty
          ? store.newId()
          : previousDescriptors.single['id'];
      await _phase(jobId, 'prepared');
      final playback = IosLessonPlayback.instance;
      for (final book in {id, ...displacedBooks}) {
        unavailable.add(book);
        blockedBooks.add(book);
        await playback.blockBook(book).timeout(const Duration(seconds: 5));
      }
      // Reserve the write queue from filesystem preparation through commit.
      await store.write(() async {
        await _checkpoint('before-media');
        final targetPath = '${store.root.path}/resources/$folder/mp3';
        final hadAudio = await _resourceEntityExists(targetPath);
        await store.db.update(
          'yzc_resource_job',
          {
            'phase': 'moving_audio',
            'had_audio': hadAudio ? 1 : 0,
            'update_time': nowMs(),
          },
          where: 'id=?',
          whereArgs: [jobId],
        );
        if (hadAudio) {
          await Directory(backup).parent.create(recursive: true);
          await _moveResourceEntity(targetPath, backup);
          await _excludeDownloadsFromBackup();
        }
        await _copyAudio(
          Directory('$staging/extracted/$folder/mp3'),
          Directory(targetPath),
        );
        await _checkpoint('media-staged');
        await store.db.update(
          'yzc_resource_job',
          {'phase': 'audio_ready', 'audio_ready': 1, 'update_time': nowMs()},
          where: 'id=?',
          whereArgs: [jobId],
        );
        final input = sourceDatabase;
        final counts = <String, int>{};
        for (final table in tables) {
          counts[table] =
              Sqflite.firstIntValue(
                await input.rawQuery('SELECT COUNT(*) FROM $table'),
              ) ??
              0;
        }
        final total = counts.values.fold<int>(0, (a, b) => a + b);
        var inserted = 0;
        await store.db.transaction((tx) async {
          task.check();
          for (final displaced in displacedBooks) {
            for (final table in textbookContentTables.reversed) {
              await tx.delete(
                table,
                where: 'textbook_id=?',
                whereArgs: [displaced],
              );
            }
            await tx.delete(
              'yzc_resource_install',
              where: 'textbook_id=?',
              whereArgs: [displaced],
            );
            await tx.delete(
              'yzc_resource',
              where: 'textbook_id=?',
              whereArgs: [displaced],
            );
            await tx.delete(
              'yzc_textbook',
              where: 'id=?',
              whereArgs: [displaced],
            );
          }
          // Replace this book's content using the current textbook schema.
          for (final table in textbookContentTables.reversed) {
            await tx.delete(table, where: 'textbook_id=?', whereArgs: [id]);
          }
          final localBookColumns = (await tx.rawQuery(
            'PRAGMA table_info(yzc_textbook)',
          )).map((row) => textOf(row, 'name')).toSet();
          final book =
              Map<String, Object?>.from(
                (await input.query('yzc_textbook')).single,
              )..removeWhere(
                (key, _) =>
                    !localBookColumns.contains(key) ||
                    key == 'resource_file' ||
                    key == 'sha256',
              );
          final bookChanged = await tx.update(
            'yzc_textbook',
            book,
            where: 'id=?',
            whereArgs: [id],
          );
          if (bookChanged == 0) await tx.insert('yzc_textbook', book);
          // The current server catalog is authoritative for every matching
          // textbook field. Keep only the installed textbook's primary key.
          final publishedBook = Map<String, Object?>.from(remoteBook)
            ..remove('id');
          await tx.update(
            'yzc_textbook',
            publishedBook,
            where: 'id=?',
            whereArgs: [id],
          );
          for (final table in tables) {
            final columns = (await tx.rawQuery('PRAGMA table_info($table)'))
                .map((r) => r['name'] as String)
                .toList();
            final localColumns = columns.toSet();
            final sourceNames = (await input.rawQuery(
              'PRAGMA table_info($table)',
            )).map((r) => textOf(r, 'name')).toSet();
            final selectedColumns = columns
                .where(sourceNames.contains)
                .toList();
            for (var offset = 0; offset < counts[table]!; offset += 200) {
              task.check();
              final rows = await input.query(
                table,
                columns: selectedColumns,
                orderBy: 'id',
                limit: 200,
                offset: offset,
              );
              final batch = tx.batch();
              for (final sourceRow in rows) {
                if (!shouldImportResourceRow(validation, table, sourceRow))
                  continue;
                final row = normalizeResourceRowForImport(
                  sourceRow,
                  localColumns,
                );
                batch.insert(
                  table,
                  row,
                  conflictAlgorithm: ConflictAlgorithm.abort,
                );
              }
              await batch.commit(noResult: true);
              inserted += rows.length;
              report(
                'sync',
                .6 + .35 * (total == 0 ? 1 : inserted / total),
                '同步数据 $inserted/$total',
              );
            }
          }
          await _checkpoint('before-db-commit');
          final installed = {
            'id': old?['id'] ?? store.newId(),
            'textbook_id': id,
            'folder': folder,
            'status': 'ready',
            'job_id': jobId,
            'install_time': nowMs(),
          };
          final changed = await tx.update(
            'yzc_resource_install',
            installed,
            where: 'textbook_id=?',
            whereArgs: [id],
          );
          if (changed == 0) await tx.insert('yzc_resource_install', installed);
          await tx.delete(
            'yzc_resource',
            where: 'folder=? AND textbook_id<>?',
            whereArgs: [folder, id],
          );
          await tx.delete(
            'yzc_resource',
            where: 'textbook_id=?',
            whereArgs: [id],
          );
          await tx.insert('yzc_resource', descriptor);
          await tx.update(
            'yzc_resource_operation',
            {
              'sha256': hash,
              'status': 'success',
              'phase': 'installed',
              'error': null,
              'update_time': nowMs(),
              'finish_time': nowMs(),
            },
            where: 'id=?',
            whereArgs: [jobId],
          );
          await tx.update(
            'yzc_resource_job',
            {'phase': 'db_committed', 'update_time': nowMs()},
            where: 'id=?',
            whereArgs: [jobId],
          );
          task.check();
          // The callback is about to hand COMMIT to SQLite. Cancellation after
          // this point cannot safely undo that commit, so close its UI window.
          task.finish();
          report('commit', null, '正在保存安装结果，可返回其他页面');
        });
      });
      committed = true;
      task.finish();
      _task = null;
      await sourceDatabase.close();
      source = null;
      unavailable.remove(id);
      await playback.unblockBook(id).timeout(const Duration(seconds: 5));
      blockedBooks.remove(id);
      try {
        await onCheckpoint?.call('cleanup');
        await _cleanup(job);
      } catch (cleanupError, cleanupStack) {
        SystemErrors.record(
          cleanupError,
          cleanupStack,
          module: 'textbook',
          operation: '内容恢复与清理',
          context: {'textbook_id': activeBook, 'stage': stage},
        );
        await _bestEffort(() => _phase(jobId, 'cleanup_pending'));
      }
      if (previousFolder != null &&
          previousFolder.isNotEmpty &&
          previousFolder != folder) {
        try {
          await _deleteFolderIfUnused(previousFolder);
        } catch (cleanupError, cleanupStack) {
          SystemErrors.record(
            cleanupError,
            cleanupStack,
            module: 'textbook',
            operation: '清理旧学习资源目录',
            context: {'textbook_id': id, 'folder': previousFolder},
          );
        }
      }
      report('sync', 1, '安装完成（${validation.summary}）');
    } catch (e, stack) {
      lastCancelled = e is ResourceCancelled;
      if (!committed) {
        lastError = lastCancelled
            ? '已取消，原有学习记录已保留，可随时重新下载。'
            : '${userError(e, fallback: '资源安装失败')}。学习记录已保留。';
        if (!lastCancelled) lastFailedBook = id;
      }
      if (e is! ResourceCancelled) {
        SystemErrors.record(
          e,
          stack,
          module: 'textbook',
          operation: '下载并安装内容',
          context: {
            ...diagnostics,
            'operation_id': operationId,
            'stage': stage,
            'detail': detail,
            'job_id': job?['id'],
          },
        );
      }
      await _bestEffort(() async {
        await source?.close();
      });
      source = null;
      // Audit I/O must never prevent rollback of the actual resource files.
      if (operationId != null)
        await _bestEffort(() => _failOperation(operationId!, e));
      var restored = job == null;
      if (job != null) {
        try {
          final current = (await store.db.query(
            'yzc_resource_job',
            where: 'id=?',
            whereArgs: [job['id']],
          )).single;
          await onCheckpoint?.call('rollback');
          await _recoverJob(current);
          restored = !unavailable.contains(id);
        } catch (cleanupError, cleanupStack) {
          SystemErrors.record(
            cleanupError,
            cleanupStack,
            module: 'textbook',
            operation: '内容恢复与清理',
            context: {'textbook_id': id, 'stage': stage},
          );
          await _bestEffort(() => _markBroken(job!));
        }
      }
      if (!committed && restored) {
        for (final book in blockedBooks) {
          unavailable.remove(book);
          await _bestEffort(
            () => IosLessonPlayback.instance
                .unblockBook(book)
                .timeout(const Duration(seconds: 5)),
          );
        }
      }
      if (committed) {
        lastError = null;
        lastFailedBook = null;
        // A failed mirror/cleanup cannot turn an already committed install into
        // a failed download or invite repeated installation of the same bytes.
        unavailable.remove(id);
        lastInstallSummary = '已安装，临时文件将在下次启动时清理';
      } else {
        rethrow;
      }
    } finally {
      task.finish();
      _task = null;
      activeBook = null;
      stage = '';
      progress = null;
      detail = '';
      notifyListeners();
    }
  }

  Future<void> _bestEffort(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      SystemErrors.record(
        error,
        stack,
        module: 'textbook',
        operation: '内容恢复与清理',
      );
    }
  }

  Future<void> _phase(String id, String phase) => store.write(() async {
    await store.db.update(
      'yzc_resource_job',
      {'phase': phase, 'update_time': nowMs()},
      where: 'id=?',
      whereArgs: [id],
    );
  });
  Future<void> _extract(String zip, String destination, String folder) async {
    final password = await (_password ?? ResourceConfig.restorePassword)()
        .timeout(const Duration(seconds: 10));
    _task!.check();
    await transfer.extract(
      File(zip),
      destination,
      folder,
      password,
      _task!,
      (stage, value, detail) => report(stage, value, detail),
    );
  }

  Future<TextbookValidationResult> _validate(
    Database source,
    String id,
    String folder,
  ) async {
    final issues = <ResourceContentIssue>[];
    final skippedRows = <String, Set<String>>{};
    void isolate(String table, Object? id, String message) {
      final rowId = id?.toString() ?? '';
      if (rowId.isEmpty || !(skippedRows[table] ??= <String>{}).add(rowId))
        return;
      issues.add(
        ResourceContentIssue('$table[$rowId]', message, skipped: true),
      );
    }

    var normal = 0;
    final integrity = await source.rawQuery('PRAGMA quick_check');
    if (integrity.length != 1 || integrity.single.values.single != 'ok')
      throw const FormatException('内容 SQLite 损坏');
    final schema = await source.rawQuery(
      "SELECT name,type FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'",
    );
    final names = schema
        .where((r) => r['type'] == 'table')
        .map((r) => textOf(r, 'name'))
        .toSet();
    const tables = textbookContentTables;
    final allowed = {'yzc_textbook', ...tables};
    if (!names.containsAll(allowed))
      throw const FormatException('内容数据库缺少必需数据表');
    if (schema.any(
      (r) =>
          !['table', 'index'].contains(r['type']) ||
          (r['type'] == 'table' && !allowed.contains(r['name'])),
    ))
      throw const FormatException('资源数据库含未约定结构');
    final sourceColumns = <String, List<RowData>>{};
    for (final table in ['yzc_textbook', ...tables]) {
      _task?.check();
      final actual = await source.rawQuery('PRAGMA table_info($table)');
      sourceColumns[table] = actual;
      final local = await store.db.rawQuery('PRAGMA table_info($table)');
      // Download metadata belongs to the app/server, and can be absent in old ZIPs.
      final metadata = table == 'yzc_textbook'
          ? {'resource_file', 'sha256'}
          : <String>{};
      final actualContent = actual
          .where((column) => !metadata.contains(column['name']))
          .toList();
      final localContent = local
          .where((column) => !metadata.contains(column['name']))
          .toList();
      final actualByName = {
        for (final column in actualContent) textOf(column, 'name'): column,
      };
      for (var i = 0; i < localContent.length; i++) {
        final name = textOf(localContent[i], 'name');
        final sourceColumn = actualByName[name];
        if (sourceColumn == null) {
          if (optionalTextbookContentColumns.contains(name)) continue;
          throw FormatException('$table 缺少必需字段 $name');
        }
        for (final key in ['name', 'type', 'pk']) {
          if (sourceColumn[key].toString().toLowerCase() !=
              localContent[i][key].toString().toLowerCase()) {
            throw FormatException('$table 的 ${localContent[i]['name']} 定义不符');
          }
        }
      }
    }
    final books = await source.query('yzc_textbook');
    if (books.length != 1 || books.single['id'] != id)
      throw const FormatException('包内内容 ID 不匹配');
    for (final table in tables) {
      final wrong =
          Sqflite.firstIntValue(
            await source.rawQuery(
              'SELECT COUNT(*) FROM $table WHERE textbook_id IS NULL OR textbook_id<>? OR id IS NULL OR id=?',
              [id, ''],
            ),
          ) ??
          0;
      if (wrong > 0) throw FormatException('$table 含其他内容或无效 ID');
      final columns = sourceColumns[table]!;
      // SQLite VARCHAR/INT affinity does not enforce value types by itself.
      for (var offset = 0; ; offset += 200) {
        _task?.check();
        final rows = await source.query(
          table,
          orderBy: 'id',
          limit: 200,
          offset: offset,
        );
        for (final row in rows) {
          for (final column in columns) {
            final key = textOf(column, 'name'),
                type = textOf(column, 'type').toLowerCase();
            final value = row[key];
            if (value != null &&
                (type.contains('int') ? value is! int : value is! String)) {
              // Payload and relationship faults are isolated by the common
              // lesson JOIN used by every consumer. Stable row/package
              // identity remains fatal because it cannot be guessed safely.
              if (!{'id', 'textbook_id'}.contains(key)) continue;
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
      ['yzc_words', 'lessons_id', 'yzc_lessons'],
      ['yzc_content', 'lessons_id', 'yzc_lessons'],
      ['yzc_words', 'unit_id', 'yzc_unit'],
      ['yzc_content', 'unit_id', 'yzc_unit'],
      ['yzc_grammar', 'lessons_id', 'yzc_lessons'],
      ['yzc_grammar', 'unit_id', 'yzc_unit'],
      ['yzc_ai_question', 'lessons_id', 'yzc_lessons'],
      ['yzc_ai_question', 'unit_id', 'yzc_unit'],
    ];
    for (final relation in relations) {
      final child = relation[0], column = relation[1], parent = relation[2];
      final required = column == 'lessons_id';
      final optionalPresent =
          'c.$column IS NOT NULL AND NOT (${sqlBlankExpression('c.$column')}) AND ';
      final missing =
          Sqflite.firstIntValue(
            await source.rawQuery(
              'SELECT COUNT(*) FROM $child c LEFT JOIN $parent p ON p.id=c.$column AND p.textbook_id=c.textbook_id WHERE ${required ? '' : optionalPresent}p.id IS NULL',
            ),
          ) ??
          0;
      if (missing > 0) {
        final rows = await source.rawQuery(
          'SELECT c.id FROM $child c LEFT JOIN $parent p ON p.id=c.$column AND p.textbook_id=c.textbook_id WHERE ${required ? '' : optionalPresent}p.id IS NULL',
        );
        for (final row in rows) {
          isolate(child, row['id'], '$column 关联不完整，已隔离');
        }
      }
      final unavailableParents = skippedRows[parent];
      if (unavailableParents != null && unavailableParents.isNotEmpty) {
        final rows = await source.query(child, columns: ['id', column]);
        for (final row in rows) {
          if (unavailableParents.contains(textOf(row, column))) {
            isolate(child, row['id'], '所属 $parent 已隔离，本条目一并跳过');
          }
        }
      }
    }
    for (final table in const ['yzc_words', 'yzc_content', 'yzc_grammar']) {
      final invalidRows = await source.rawQuery(
        "SELECT c.id FROM $table c JOIN yzc_lessons l ON l.id=c.lessons_id AND l.textbook_id=c.textbook_id WHERE (c.unit_id IS NOT NULL AND NOT (${sqlBlankExpression('c.unit_id')}) AND c.unit_id<>l.unit_id) OR l.unit_id IS NULL OR (c.lesson IS NOT NULL AND NOT (${sqlBlankExpression('c.lesson')}) AND c.lesson<>l.lesson) OR l.lesson IS NULL",
      );
      for (final row in invalidRows) {
        isolate(table, row['id'], '与课程、单元关联不一致，已隔离');
      }
    }
    for (final table in ['yzc_words', 'yzc_content']) {
      final names = await source.rawQuery(
        'SELECT DISTINCT phonetic FROM $table WHERE phonetic IS NOT NULL AND phonetic<>?',
        [''],
      );
      for (final row in names) {
        final name = textOf(row, 'phonetic');
        try {
          safeName(name);
          if (!name.toLowerCase().endsWith('.mp3') ||
              !await File('$folder/mp3/$name').exists()) {
            issues.add(
              ResourceContentIssue('$table.phonetic[$name]', '音频缺失，播放按钮已降级'),
            );
          } else {
            normal++;
          }
        } on FormatException catch (error) {
          issues.add(
            ResourceContentIssue('$table.phonetic[$name]', '$error，播放按钮已降级'),
          );
        }
      }
    }
    final invalid = await source.rawQuery(
      "SELECT q.id FROM yzc_ai_question q JOIN yzc_lessons l ON l.id=q.lessons_id AND l.textbook_id=q.textbook_id WHERE (q.unit_id IS NOT NULL AND NOT (${sqlBlankExpression('q.unit_id')}) AND q.unit_id<>l.unit_id) OR l.unit_id IS NULL OR (q.lesson IS NOT NULL AND NOT (${sqlBlankExpression('q.lesson')}) AND q.lesson<>l.lesson) OR l.lesson IS NULL",
    );
    for (final row in invalid) {
      isolate('yzc_ai_question', row['id'], '与课程、单元关联不一致，已隔离');
    }
    for (var offset = 0; ; offset += 200) {
      _task?.check();
      final questions = await source.query(
        'yzc_ai_question',
        orderBy: 'id',
        limit: 200,
        offset: offset,
      );
      for (final question in questions) {
        final location = 'yzc_ai_question[${question['id']}]';
        if (skippedRows['yzc_ai_question']?.contains(textOf(question, 'id')) ==
            true)
          continue;
        if (!isReadableQuestion({
          ...question,
          'content': question['question'],
        })) {
          isolate('yzc_ai_question', question['id'], '题干或分类无效，已隔离');
          continue;
        }
        final mode = questionAnswerMode(question);
        if (mode.degraded) {
          issues.add(ResourceContentIssue(location, '${mode.issue}，已排除自动评分'));
        } else {
          normal++;
        }
      }
      if (questions.length < 200) break;
    }
    for (final table in const [
      'yzc_words',
      'yzc_content',
      'yzc_grammar',
      'yzc_ai_question',
    ]) {
      for (var offset = 0; ; offset += 200) {
        _task?.check();
        final rows = await source.query(
          table,
          orderBy: 'id',
          limit: 200,
          offset: offset,
        );
        for (final row in rows) {
          final type = textOf(row, 'media_type');
          if (type.isEmpty || type == 'text') continue;
          final location = '$table[${row['id']}]';
          String filename;
          try {
            filename = textbookMediaFilename(textOf(row, 'media_src'), type);
          } on FormatException catch (error) {
            issues.add(ResourceContentIssue(location, '$error，媒体已降级'));
            continue;
          }
          if (!await File('$folder/mp3/$filename').exists()) {
            issues.add(
              ResourceContentIssue(location, '缺少媒体 $filename，已使用占位提示'),
            );
            continue;
          }
          final mediaConfig = textOf(row, 'media_config');
          if (type == 'interactive_image') {
            final parsed = CourseImageInteractionConfig.parseTolerant(
              mediaConfig,
            );
            for (final issue in parsed.issues) {
              issues.add(
                ResourceContentIssue(
                  '$location.media_config',
                  issue,
                  skipped: issue.startsWith('热点'),
                ),
              );
            }
            final config = parsed.config;
            if (config == null) continue;
            for (final hotspot in config.hotspots) {
              if (!await File('$folder/mp3/${hotspot.audioSource}').exists()) {
                issues.add(
                  ResourceContentIssue(
                    '$location.hotspot[${hotspot.id}]',
                    '缺少音频 ${hotspot.audioSource}，已禁用',
                    skipped: true,
                  ),
                );
              } else {
                normal++;
              }
            }
          } else {
            normal++;
          }
        }
        if (rows.length < 200) break;
      }
    }
    var suppliedLearningRows = 0, usableLearningRows = 0;
    for (final table in const [
      'yzc_words',
      'yzc_content',
      'yzc_grammar',
      'yzc_ai_question',
    ]) {
      final count =
          Sqflite.firstIntValue(
            await source.rawQuery('SELECT COUNT(*) FROM $table'),
          ) ??
          0;
      suppliedLearningRows += count;
      usableLearningRows += count - (skippedRows[table]?.length ?? 0);
    }
    if (suppliedLearningRows > 0 && usableLearningRows == 0) {
      throw const FormatException('资源包的学习条目全部无法安全使用，已保留旧版内容');
    }
    if (suppliedLearningRows == 0) {
      var installedLearningRows = 0;
      for (final table in const [
        'yzc_words',
        'yzc_content',
        'yzc_grammar',
        'yzc_ai_question',
      ]) {
        installedLearningRows +=
            Sqflite.firstIntValue(
              await store.db.rawQuery(
                'SELECT COUNT(*) FROM $table WHERE textbook_id=?',
                [id],
              ),
            ) ??
            0;
      }
      if (installedLearningRows > 0) {
        throw const FormatException('新资源包不含学习条目，已保留旧版内容');
      }
    }
    return TextbookValidationResult(
      tables: tables,
      normal: normal,
      issues: List.unmodifiable(issues),
      skippedRows: {
        for (final entry in skippedRows.entries)
          entry.key: Set.unmodifiable(entry.value),
      },
    );
  }

  @visibleForTesting
  Future<TextbookValidationResult> validateForTesting(
    Database source,
    String id,
    String folder,
  ) => _validate(source, id, folder);
  Future<void> _copyAudio(Directory from, Directory to) async {
    final files = await from
        .list()
        .where((f) => f is File)
        .cast<File>()
        .toList();
    int total = 0, copied = 0;
    for (final file in files) {
      total += await file.length();
    }
    final capacity = await transfer.capacity();
    _task?.check();
    if (capacity != null && capacity < total + 128 * 1024 * 1024)
      throw StateError('同步学习资源的空间不足');
    await to.create(recursive: true);
    await _excludeDownloadsFromBackup();
    for (final file in files) {
      _task?.check();
      final output = await File('${to.path}/${file.uri.pathSegments.last}')
          .open(mode: FileMode.write);
      try {
        await for (final bytes in file.openRead()) {
          _task?.check();
          await output.writeFrom(bytes);
          copied += bytes.length;
          report(
            'sync',
            total == 0 ? .6 : .6 * copied / total,
            '复制学习资源 $copied/$total 字节',
          );
        }
        await output.flush();
      } finally {
        await output.close();
      }
    }
    report('sync', .6, '学习资源已就位');
  }

  Future<void> _excludeDownloadsFromBackup() async {
    if (Platform.isIOS) {
      await const MethodChannel('yuzhichu/device')
          .invokeMethod<void>('excludeDownloadedResourcesFromBackup')
          .timeout(const Duration(seconds: 5));
    }
  }

  Future<void> recover() async {
    await _cleanFailedStaging();
    try {
      await _excludeDownloadsFromBackup();
    } catch (e, stack) {
      // A backup attribute failure must not block existing offline learning.
      SystemErrors.record(e, stack, module: 'textbook', operation: '设置资源备份属性');
    }
    final jobs = await store.db.query(
      'yzc_resource_job',
      where: 'phase NOT IN (?,?)',
      whereArgs: ['done', 'failed'],
      orderBy: 'create_time',
    );
    for (final job in jobs) {
      try {
        await _recoverJob(job);
      } catch (cleanupError, cleanupStack) {
        SystemErrors.record(
          cleanupError,
          cleanupStack,
          module: 'textbook',
          operation: '内容恢复与清理',
          context: {'textbook_id': activeBook, 'stage': stage},
        );
        await _bestEffort(() => _markBroken(job));
      }
    }
    final operations = await store.db.query(
      'yzc_resource_operation',
      where: 'status=?',
      whereArgs: ['running'],
      orderBy: 'create_time,id',
    );
    for (final operation in operations) {
      if (operation['action'] == 'delete' &&
          operation['phase'] == 'db_committed') {
        final id = textOf(operation, 'textbook_id');
        try {
          await _finishDelete(operation);
          await IosLessonPlayback.instance
              .unblockBook(id)
              .timeout(const Duration(seconds: 5));
        } catch (e, stack) {
          SystemErrors.record(
            e,
            stack,
            module: 'textbook',
            operation: '恢复内容删除',
            context: {'textbook_id': id, 'operation_id': operation['id']},
          );
          unavailable.add(id);
          await store.write(
            () => store.db.update(
              'yzc_resource_operation',
              {'error': e.toString(), 'update_time': nowMs()},
              where: 'id=?',
              whereArgs: [operation['id']],
            ),
          );
          await IosLessonPlayback.instance
              .blockBook(id)
              .timeout(const Duration(seconds: 5));
        }
      } else {
        await _bestEffort(
          () => _failOperation(textOf(operation, 'id'), '操作因应用退出而中断，未完成安装或删除'),
        );
      }
    }
    // A system backup retains learning data, but deliberately omits media.
    for (final row in await installations()) {
      if (row['status'] != 'ready') continue;
      final folder = textOf(row, 'folder');
      safeName(folder);
      if (!await Directory('${store.root.path}/resources/$folder/mp3')
          .exists()) {
        final id = textOf(row, 'textbook_id');
        await store.write(
          () => store.db.update(
            'yzc_resource_install',
            {'status': 'broken'},
            where: 'textbook_id=?',
            whereArgs: [id],
          ),
        );
        unavailable.add(id);
        await IosLessonPlayback.instance
            .blockBook(id)
            .timeout(const Duration(seconds: 5));
      }
    }
  }

  Future<void> _recoverJob(RowData job) async {
    final id = textOf(job, 'textbook_id'), folder = textOf(job, 'folder');
    safeName(folder);
    final installed = await installation(id);
    if (installed?['job_id'] == job['id']) {
      final target = Directory('${store.root.path}/resources/$folder/mp3');
      if (!await target.exists()) {
        unavailable.add(id);
        throw StateError('新版音频丢失，请重新下载');
      }
      try {
        await onCheckpoint?.call('cleanup');
        await _cleanup(job);
      } catch (cleanupError, cleanupStack) {
        SystemErrors.record(
          cleanupError,
          cleanupStack,
          module: 'textbook',
          operation: '内容恢复与清理',
          context: {'textbook_id': activeBook, 'stage': stage},
        );
        await _bestEffort(() => _phase(textOf(job, 'id'), 'cleanup_pending'));
      }
      unavailable.remove(id);
      await _bestEffort(
        () => IosLessonPlayback.instance
            .unblockBook(id)
            .timeout(const Duration(seconds: 5)),
      );
      return;
    }
    final phase = textOf(job, 'phase');
    if (!['download', 'prepared'].contains(phase)) {
      final targetPath = '${store.root.path}/resources/$folder/mp3';
      final backupPath = textOf(job, 'backup');
      if (await _resourceEntityExists(backupPath)) {
        // Persist rollback intent before changing files. If we crash after
        // rename, the surviving target is already the restored old directory.
        await _phase(textOf(job, 'id'), 'rolling_back');
        if (await _resourceEntityExists(targetPath))
          await _deleteResourceEntity(targetPath);
        await _moveResourceEntity(backupPath, targetPath);
        await _bestEffort(_excludeDownloadsFromBackup);
      } else if (intOf(job, 'had_audio') == 0) {
        if (await _resourceEntityExists(targetPath))
          await _deleteResourceEntity(targetPath);
      } else if (!['moving_audio', 'rolling_back'].contains(phase) ||
          !await _resourceEntityExists(targetPath)) {
        unavailable.add(id);
        throw StateError('旧音频备份缺失，需重新下载');
      }
    }
    // The old media has been restored. Mark that terminal state before optional
    // garbage collection; disk-full cleanup errors must not mark good data broken.
    await _bestEffort(() => _phase(textOf(job, 'id'), 'failed'));
    await _bestEffort(() => _failOperation(textOf(job, 'id'), '安装中断，已恢复原内容状态'));
    await _bestEffort(() async {
      final staging = Directory(textOf(job, 'staging'));
      if (await staging.exists()) await staging.delete(recursive: true);
    });
    unavailable.remove(id);
    if (activeBook == null && lastError == null) {
      lastError = '上次下载因应用退出而中断，已恢复原内容状态，可重新下载。';
      lastFailedBook = id;
    }
    if (installed?['status'] == 'broken') {
      final oldFolder = textOf(installed!, 'folder');
      safeName(oldFolder);
      if (intOf(job, 'had_audio') == 1 &&
          await Directory('${store.root.path}/resources/$oldFolder/mp3')
              .exists()) {
        await store.write(
          () => store.db.update(
            'yzc_resource_install',
            {'status': 'ready'},
            where: 'textbook_id=?',
            whereArgs: [id],
          ),
        );
      } else {
        unavailable.add(id);
      }
    }
    if (!unavailable.contains(id))
      await _bestEffort(
        () => IosLessonPlayback.instance
            .unblockBook(id)
            .timeout(const Duration(seconds: 5)),
      );
  }

  Future<void> _markBroken(RowData job) async {
    final id = textOf(job, 'textbook_id');
    final installed = await installation(id);
    final currentRows = await store.db.query(
      'yzc_resource_job',
      where: 'id=?',
      whereArgs: [job['id']],
    );
    final hasBackup = await _resourceEntityExists(textOf(job, 'backup'));
    final currentPhase = currentRows.isEmpty
        ? null
        : currentRows.single['phase'];
    // Failing to log or clean up an untouched old install is not corruption.
    if (installed != null &&
        (['download', 'prepared'].contains(currentPhase) ||
            textOf(installed, 'folder') != textOf(job, 'folder'))) {
      final oldFolder = textOf(installed, 'folder');
      safeName(oldFolder);
      if (await Directory('${store.root.path}/resources/$oldFolder/mp3')
          .exists()) {
        unavailable.remove(id);
        return;
      }
    }
    unavailable.add(id);
    await store.write(
      () => store.db.transaction((tx) async {
        await tx.update(
          'yzc_resource_install',
          {'status': 'broken'},
          where: 'textbook_id=?',
          whereArgs: [id],
        );
        await tx.update(
          'yzc_resource_job',
          {
            if (!hasBackup) 'phase': 'failed',
            'error': '恢复失败，等待恢复或重新下载',
            'update_time': nowMs(),
          },
          where: 'id=?',
          whereArgs: [job['id']],
        );
        await tx.update(
          'yzc_resource_operation',
          {
            'status': 'failed',
            'error': '恢复失败，等待重新下载',
            'update_time': nowMs(),
            'finish_time': nowMs(),
          },
          where: 'id=? AND status=?',
          whereArgs: [job['id'], 'running'],
        );
      }),
    );
    await IosLessonPlayback.instance
        .blockBook(id)
        .timeout(const Duration(seconds: 5));
  }

  Future<void> _cleanFailedStaging({String? id}) async {
    // Terminal failures may leave garbage when the disk was temporarily full.
    // Only their private staging is retried here; never replay a media swap.
    await _bestEffort(() async {
      final jobs = await store.db.query(
        'yzc_resource_job',
        where: id == null ? 'phase=?' : 'phase=? AND textbook_id=?',
        whereArgs: ['failed', if (id != null) id],
      );
      for (final job in jobs) {
        final jobId = textOf(job, 'id');
        safeName(jobId);
        final expected = '${store.root.path}/staging/$jobId';
        if (textOf(job, 'staging') != expected) continue;
        await _bestEffort(() async {
          if (await _resourceEntityExists(expected))
            await _deleteResourceEntity(expected);
        });
      }
    });
  }

  Future<void> _cleanup(RowData job) async {
    for (final path in [textOf(job, 'backup'), textOf(job, 'staging')]) {
      if (await _resourceEntityExists(path)) await _deleteResourceEntity(path);
    }
    await _phase(textOf(job, 'id'), 'done');
  }

  Future<void> _deleteFolderIfUnused(String folder) async {
    safeName(folder);
    final references = await store.db.query(
      'yzc_resource_install',
      columns: ['id'],
      where: 'folder=?',
      whereArgs: [folder],
      limit: 1,
    );
    if (references.isNotEmpty) return;
    final path = '${store.root.path}/resources/$folder';
    if (await _resourceEntityExists(path)) await _deleteResourceEntity(path);
  }
}
