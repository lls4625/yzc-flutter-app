import 'package:flutter/material.dart';
import 'repository.dart';

// All targets and actions belong exclusively to this demo's pages.
class JlptDemoController {
  final repository = JlptRepository();
  final navigator = GlobalKey<NavigatorState>();
  final selection = GlobalKey(), startTarget = GlobalKey(), readyTarget = GlobalKey();
  final questionTarget = GlobalKey(), resultTarget = GlobalKey();
  VoidCallback? start, resume, answerWrong, answerCorrect, showTranscript;
  Future<void> Function()? nextPhase, submit;
}
