import 'package:flutter/material.dart';

import 'guide.dart';

void showJlptPracticeDemo(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const JlptDemoGuide()));
}
