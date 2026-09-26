import '../../../system_errors.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../foundation/native_audio_transport.dart';
import '../../host_contracts.dart';

/// Remains mounted with the room so background listening observes revocation.
class ListeningPlaybackPolicy {
  ListeningPlaybackPolicy(this.host) {
    host.changes.addListener(_changed);
    _player.addListener(_changed);
    scheduleMicrotask(_changed);
  }
  final StudyRoomHost host;
  final _player = NativeAudioTransport.instance;
  bool _stopping = false, _disposed = false;
  void _changed() {
    if (_disposed) return;
    final identity = _player.lesson ?? '';
    final delimiter = identity.indexOf(':listening:');
    if (delimiter < 0 || !_player.active || _player.stopping || _stopping)
      return;
    final book = identity.substring(0, delimiter);
    if (!host.isUnlocked() || host.isBookUnavailable(book)) unawaited(_stop());
  }

  Future<void> _stop() async {
    _stopping = true;
    try {
      await _player.stop();
    } catch (e, caughtStack) {
      SystemErrors.record(e, caughtStack, module: 'listening', operation: '停止受限音频', context: {'source': 'study_room/listening/feature/playback_policy.dart'});
      debugPrint('Listening access stop failed: $e');
    } finally {
      _stopping = false;
    }
  }

  void dispose() {
    _disposed = true;
    host.changes.removeListener(_changed);
    _player.removeListener(_changed);
  }
}
