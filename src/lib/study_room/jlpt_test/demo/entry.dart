import 'package:flutter/material.dart';

import 'guide.dart';

void showJlptTestDemo(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const JlptDemoGuide()));
}
