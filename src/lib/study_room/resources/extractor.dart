import '../../resource_archive_extractor.dart';

// Runs in a worker isolate; no SQLite or platform channels in this isolate.
void extractStudyWorker(List<Object> args) {
  extractResourceArchiveWorker(args);
}
