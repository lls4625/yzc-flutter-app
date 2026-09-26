import 'package:flutter/material.dart';

import 'host_contracts.dart';
import 'access/access.dart';
import 'home/page.dart';
import 'listening/feature/playback_policy.dart';
export 'host_contracts.dart';
export 'access/purchase.dart';
export 'access/purchase_section.dart';

class StudyRoomModule extends StatefulWidget {
  const StudyRoomModule(this.host, {super.key});
  final StudyRoomHost host;
  @override
  State<StudyRoomModule> createState() => _StudyRoomModuleState();
}

class _StudyRoomModuleState extends State<StudyRoomModule> {
  late StudyRoomAccess _access;
  late ListeningPlaybackPolicy _listeningPolicy;
  @override
  void initState() {
    super.initState();
    _wire();
  }

  void _wire() {
    _access = StudyRoomAccess(widget.host);
    _listeningPolicy = ListeningPlaybackPolicy(widget.host);
  }

  @override
  void didUpdateWidget(StudyRoomModule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.host != widget.host) {
      _listeningPolicy.dispose();
      _wire();
    }
  }

  @override
  void dispose() {
    _listeningPolicy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StudyRoomPage(widget.host, _access);
}
