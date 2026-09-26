import 'package:flutter/material.dart';
import 'repository.dart';

class JlptDemoController {
  final repository = JlptRepository();
  final navigator = GlobalKey<NavigatorState>();
  final selection = GlobalKey(), startTarget = GlobalKey(), readyTarget = GlobalKey();
  final questionTarget = GlobalKey(), resultTarget = GlobalKey(), mistakesTarget = GlobalKey();
  VoidCallback? start, resume, answerWrong, reveal, clear, answerCorrect, next, openMistakes, home;
  Future<void> Function()? submit;
}
