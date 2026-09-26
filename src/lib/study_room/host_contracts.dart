import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'resources/manager.dart';

typedef StudyWrite = Future<T> Function<T>(Future<T> Function() action);

/// Immutable wiring only. Feature state and repositories never live here.
class StudyRoomHost {
  const StudyRoomHost({
    required this.userId,
    required this.rootPath,
    required this.contentDatabasePath,
    required this.changes,
    required this.isUnlocked,
    required this.isPurchaseSaving,
    required this.isBookUnavailable,
    required this.audioPath,
    required this.playbackSpeed,
    required this.openPurchase,
    required this.database,
    required this.write,
    required this.newId,
    required this.resources,
  });
  final String userId, rootPath, contentDatabasePath;
  final Listenable changes;
  final bool Function() isUnlocked, isPurchaseSaving;
  final bool Function(String) isBookUnavailable;
  final Future<String> Function(String book, String filename) audioPath;
  final double Function() playbackSpeed;
  final VoidCallback openPurchase;
  final Database database;
  final StudyWrite write;
  final String Function() newId;
  final StudyResources resources;
}
