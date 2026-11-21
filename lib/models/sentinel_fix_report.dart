import 'package:flutter/foundation.dart';

/// Outcome of one repair step in a fix-all run.
enum SentinelFixStatus {
  /// The step ran and the router confirmed it.
  fixed,

  /// The step ran but the router reported a failure (or refused the call).
  failed,

  /// The step does not apply to this router (component not installed).
  skipped,
}

/// One step of a fix-all run, as a value.
///
/// [id] is a stable key the screen translates; [detail] is untranslated
/// router output (a service name, an error) shown verbatim.
@immutable
class SentinelFixStep {
  const SentinelFixStep({required this.id, required this.status, this.detail});

  final String id;
  final SentinelFixStatus status;
  final String? detail;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SentinelFixStep &&
          other.id == id &&
          other.status == status &&
          other.detail == detail;

  @override
  int get hashCode => Object.hash(id, status, detail);
}

/// What a fix-all run repaired and what it could not.
@immutable
class SentinelFixReport {
  const SentinelFixReport(this.steps);

  final List<SentinelFixStep> steps;

  int get fixedCount =>
      steps.where((s) => s.status == SentinelFixStatus.fixed).length;
  int get failedCount =>
      steps.where((s) => s.status == SentinelFixStatus.failed).length;
  int get skippedCount =>
      steps.where((s) => s.status == SentinelFixStatus.skipped).length;

  /// True when nothing that applied to this router was left broken.
  bool get allFixed => failedCount == 0;
}
