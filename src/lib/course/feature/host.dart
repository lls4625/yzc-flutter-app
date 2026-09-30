import 'package:flutter/foundation.dart';
import '../../data.dart';
import '../../resources.dart';

/// Narrow host boundary used by the four independent course-tab modules.
abstract interface class CourseTabHost implements Listenable {
  AppStore get store;
  Resources get resources;
  bool get ruby;
  bool get source;
  bool get translation;
  double get speed;
  Future<void> setting(String key, Object value);
  Future<void> reload();
}
