import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// 41 timestamp bits + 10 worker bits + 12 sequence bits, stored as text.
/// Worker 0 is reserved for resource authoring; app workers are 1–1023.
class SnowflakeIds {
  SnowflakeIds(this.directory, {required int floorId}) : _floor = (floorId >> 22) + 1;

  static const epoch = 1288834974657;
  static const _reservation = 4096 * 1000;
  final Directory directory;
  final int _floor;
  int _next = 0, _end = 0, _worker = 0;

  String next() {
    final wall = DateTime.now().millisecondsSinceEpoch - epoch;
    if (wall < 0) throw StateError('系统时间早于雪花 ID 起始时间');
    _next = max(_next, wall << 12);
    if (_next >= _end) _reserve();
    final token = _next++;
    return (((token >> 12) << 22) | (_worker << 12) | (token & 4095)).toString();
  }

  void _reserve() {
    directory.createSync(recursive: true);
    final lock = File('${directory.path}/snowflake.lock').openSync(mode: FileMode.append);
    try {
      lock.lockSync(FileLock.blockingExclusive);
      final file = File('${directory.path}/snowflake.json');
      int high = _floor << 12;
      if (file.existsSync()) {
        final state = jsonDecode(file.readAsStringSync(encoding: utf8));
        if (state is! Map || state['version'] != 1 || state['worker'] is! int || state['next'] is! String) {
          throw StateError('雪花 ID 状态无法读取，请勿删除状态文件');
        }
        _worker = state['worker'] as int;
        final saved = int.tryParse(state['next'] as String);
        if (_worker < 1 || _worker > 1023 || saved == null || saved < 0) {
          throw StateError('雪花 ID 状态无效，请勿重置');
        }
        high = max(high, saved);
      } else {
        const configured = int.fromEnvironment('SNOWFLAKE_WORKER_ID', defaultValue: -1);
        if (configured != -1 && (configured < 1 || configured > 1023)) {
          throw StateError('SNOWFLAKE_WORKER_ID 必须在 1–1023 之间');
        }
        _worker = configured == -1 ? Random.secure().nextInt(1023) + 1 : configured;
      }
      final start = max(_next, high);
      final end = start + _reservation;
      if ((end >> 12) >= (1 << 41)) throw StateError('雪花 ID 时间范围已耗尽');
      // Persist the whole reserved range before returning any ID. A crash may
      // skip unused IDs, but cannot cause a committed range to be allocated twice.
      final temporary = File('${file.path}.next');
      temporary.writeAsStringSync(jsonEncode({'version': 1, 'worker': _worker, 'next': end.toString()}), encoding: utf8, flush: true);
      temporary.renameSync(file.path);
      _next = start;
      _end = end;
    } finally {
      lock.closeSync();
    }
  }
}
