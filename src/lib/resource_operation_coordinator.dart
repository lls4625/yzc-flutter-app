import 'package:flutter/foundation.dart';

enum ResourceOperationKind {
  textbookInstall,
  textbookDelete,
  textbookSelect,
  studyInstall,
  studyDelete,
  cleanup,
  recovery,
}

enum ResourceOperationStage {
  preflight,
  catalog,
  spaceCheck,
  download,
  verify,
  extract,
  validate,
  prepareInstall,
  installMedia,
  commit,
  activation,
  cleanup,
  rollback,
}

class ResourceOperationLease {
  ResourceOperationLease._(
    this.kind,
    this.target,
    this.label,
    this.startedAt,
  );

  final ResourceOperationKind kind;
  final String target;
  final String label;
  final DateTime startedAt;
}

/// Process-wide ownership for every operation that can change installed
/// learning or self-study resources. It rejects contention instead of queuing.
class ResourceOperationCoordinator extends ChangeNotifier {
  ResourceOperationLease? _active;
  ResourceOperationStage? _stage;
  double? _progress;
  bool _canCancel = false;
  bool _cancelling = false;

  ResourceOperationLease? get active => _active;
  bool get busy => _active != null;
  String? get label => _active?.label;
  ResourceOperationStage? get stage => _stage;
  double? get progress => _progress;
  bool get canCancel => _canCancel;
  bool get cancelling => _cancelling;

  ResourceOperationLease acquire(
    ResourceOperationKind kind,
    String target,
    String label,
  ) {
    if (_active != null) {
      throw StateError('正在处理其他资源，请完成后重试');
    }
    final lease = ResourceOperationLease._(
      kind,
      target,
      label,
      DateTime.now().toUtc(),
    );
    _active = lease;
    _stage = ResourceOperationStage.preflight;
    _progress = null;
    _canCancel = false;
    _cancelling = false;
    notifyListeners();
    return lease;
  }

  bool owns(ResourceOperationLease lease) => identical(_active, lease);

  void update(
    ResourceOperationLease lease,
    ResourceOperationStage stage, {
    double? progress,
    bool canCancel = false,
    bool cancelling = false,
  }) {
    if (!owns(lease)) return;
    _stage = stage;
    _progress = progress;
    _canCancel = canCancel;
    _cancelling = cancelling;
    notifyListeners();
  }

  void release(ResourceOperationLease lease) {
    if (!owns(lease)) return;
    _active = null;
    _stage = null;
    _progress = null;
    _canCancel = false;
    _cancelling = false;
    notifyListeners();
  }
}
