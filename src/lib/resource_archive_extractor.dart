import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';

class _CheckedOutputFileStream extends OutputFileStream {
  _CheckedOutputFileStream(
    String path, {
    required this.expectedSize,
    required this.onBytes,
  }) : super.withFileHandle(FileHandle(path, mode: FileAccess.write));

  final int expectedSize;
  final void Function(int count) onBytes;
  int crc32 = 0;

  void _checkLength(int count) {
    if (length + count > expectedSize) {
      throw const FormatException('ZIP 实际解压大小超过声明大小');
    }
  }

  @override
  void writeByte(int value) {
    _checkLength(1);
    crc32 = getCrc32(<int>[value], crc32);
    super.writeByte(value);
    onBytes(1);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    _checkLength(count);
    crc32 = getCrc32(
        count == bytes.length ? bytes : bytes.sublist(0, count), crc32);
    super.writeBytes(bytes, length: count);
    onBytes(count);
  }
}

// Runs in a worker isolate; no SQLite or platform channels in this isolate.
void extractResourceArchiveWorker(List<Object> args) {
  final port = args[0] as SendPort;
  final zip = args[1] as String;
  final destination = args[2] as String;
  final folder = args[3] as String;
  InputFileStream? input;
  try {
    input = InputFileStream(zip);
    final decoder = ZipDecoder();
    final archive = decoder.decodeStream(input, password: args[4] as String);
    if (archive.files.length != decoder.directory.fileHeaders.length) {
      throw const FormatException('ZIP 含重复条目');
    }

    final entries = <(ArchiveFile, String)>[];
    final pathTypes = <String, bool>{};
    int total = 0;
    bool database = false;
    bool mediaDirectory = false;
    final databasePath = '$folder/data.sqlite';
    final mediaPath = '$folder/mp3';

    for (final file in archive.files) {
      var name = file.name;
      if (name.endsWith('/')) name = name.substring(0, name.length - 1);
      final parts = name.split('/');
      if (file.isSymbolicLink ||
          parts.any((part) =>
              part.isEmpty ||
              part == '.' ||
              part == '..' ||
              part.contains('\\') ||
              part.contains(':') ||
              part.contains('\u0000'))) {
        throw FormatException('ZIP 路径不安全：${file.name}');
      }

      final key = name.toLowerCase();
      if (pathTypes.containsKey(key)) {
        throw FormatException('ZIP 含重复路径：$name');
      }
      pathTypes[key] = file.isFile;
      entries.add((file, name));

      if (file.isFile) {
        if (file.size < 0) throw FormatException('ZIP 文件大小无效：$name');
        total += file.size;
        if (name == databasePath) database = true;
      }
      if ((!file.isFile && name == mediaPath) || name.startsWith('$mediaPath/')) {
        mediaDirectory = true;
      }
    }

    for (final entry in entries) {
      final name = entry.$2.toLowerCase();
      final parts = name.split('/');
      for (var i = 1; i < parts.length; i++) {
        final parent = parts.take(i).join('/');
        if (pathTypes[parent] == true) {
          throw FormatException('ZIP 文件与目录路径冲突：${entry.$2}');
        }
      }
    }

    if (!database) throw const FormatException('资源包缺少 data.sqlite');
    if (!mediaDirectory) throw const FormatException('资源包缺少 mp3 文件夹');

    final capacity = args[5] as int;
    final required = total * 2 + 512 * 1024 * 1024;
    if (capacity >= 0 && capacity < required) {
      throw FormatException('解压及同步所需存储空间不足：可用 $capacity，需要 $required');
    }

    for (final entry in entries.where((entry) => !entry.$1.isFile)) {
      Directory('$destination/${entry.$2}').createSync(recursive: true);
    }

    int written = 0;
    int lastReported = 0;
    for (final entry in entries.where((entry) => entry.$1.isFile)) {
      final file = entry.$1;
      final name = entry.$2;
      final outputFile = File('$destination/$name');
      outputFile.parent.createSync(recursive: true);
      final output = _CheckedOutputFileStream(
        outputFile.path,
        expectedSize: file.size,
        onBytes: (count) {
          written += count;
          if (written - lastReported >= 65536 || written == total) {
            lastReported = written;
            final progress = total == 0 ? 1.0 : written / total;
            port.send({'progress': progress > 1 ? 1.0 : progress});
          }
        },
      );
      try {
        file.writeContent(output);
      } finally {
        output.closeSync();
      }

      final actualSize = output.length;
      final actualCrc = output.crc32;
      if (actualSize != file.size ||
          (file.crc32 != null && actualCrc != file.crc32)) {
        throw FormatException(
            'ZIP 内容校验失败：$name，声明大小 ${file.size}，实际大小 $actualSize，声明 CRC ${file.crc32}，实际 CRC $actualCrc');
      }
    }
    if (total == 0) port.send({'progress': 1.0});
    port.send({'done': true});
  } catch (error, stack) {
    port.send({'error': error.toString(), 'stack': stack.toString()});
  } finally {
    input?.closeSync();
  }
}
