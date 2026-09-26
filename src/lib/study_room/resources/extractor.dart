import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:archive/archive_io.dart';

// Runs in a worker isolate; no SQLite or platform channels in this isolate.
void extractStudyWorker(List<Object> args) {
  final port = args[0] as SendPort;
  final zip = args[1] as String, destination = args[2] as String, folder = args[3] as String;
  InputFileStream? input;
  try {
    input = InputFileStream(zip);
    final decoder = ZipDecoder();
    final archive = decoder.decodeBuffer(input, password: args[4] as String);
    if (archive.files.length != decoder.directory.fileHeaders.length) throw const FormatException('ZIP 含重复条目');
    final seen = <String>{};
    int total = 0;
    for (final file in archive.files) {
      var name = file.name;
      if (name.endsWith('/')) name = name.substring(0, name.length - 1);
      final parts = name.split('/');
      // Accept every file type and directory layout, including hidden files.
      // Keep extraction confined to the destination and reject ambiguous paths.
      if (file.isSymbolicLink || parts.any((p) => p.isEmpty || p == '.' || p == '..' || p.contains('\\') || p.contains(':') || p.contains('\u0000')) || !seen.add(name.toLowerCase())) throw FormatException('ZIP 目录不安全或含重复路径：$name');
      if (!file.isFile) continue;
      if (file.size < 0) throw FormatException('ZIP 文件大小无效：$name');
      total += file.size;
    }
    final capacity = args[5] as int;
    if (capacity >= 0 && capacity < total * 2 + 512 * 1024 * 1024) {
      throw FormatException('解压及同步所需存储空间不足：可用 $capacity，需要 ${total * 2 + 512 * 1024 * 1024}');
    }
    Directory('$destination/$folder/mp3').createSync(recursive: true);
    for (final file in archive.files.where((f) => !f.isFile)) {
      Directory('$destination/${file.name}').createSync(recursive: true);
    }
    int written = 0;
    for (final file in archive.files.where((f) => f.isFile)) {
      final bytes = file.content as List<int>;
      if (bytes.length != file.size || (file.crc32 != null && getCrc32(bytes) != file.crc32)) throw FormatException('ZIP 内容校验失败：${file.name}，声明大小 ${file.size}，实际大小 ${bytes.length}，声明 CRC ${file.crc32}，实际 CRC ${getCrc32(bytes)}');
      final output = File('$destination/${file.name}');
      output.parent.createSync(recursive: true);
      final sink = output.openSync(mode: FileMode.write);
      try {
        for (var start = 0; start < bytes.length; start += 65536) {
          final end = min(start + 65536, bytes.length);
          sink.writeFromSync(bytes, start, end);
          written += end - start;
          port.send({'progress': total == 0 ? 1.0 : written / total});
        }
        sink.flushSync();
      } finally { sink.closeSync(); }
      file.clear();
    }
    port.send({'done': true});
  } catch (e, stack) {
    port.send({'error': e.toString(), 'stack': stack.toString()});
  } finally { input?.closeSync(); }
}
