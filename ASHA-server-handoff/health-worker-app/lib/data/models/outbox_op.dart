import 'dart:convert';

enum OpState { pending, acknowledged, rejected, conflict }

OpState opStateFrom(String s) => OpState.values.firstWhere(
  (e) => e.name.toUpperCase() == s,
  orElse: () => OpState.pending,
);

/// One queued local change. Written in the SAME SQLite transaction as the local change it describes.
class OutboxOp {
  const OutboxOp({
    this.seq,
    required this.opId,
    required this.entityType,
    required this.entityId,
    required this.opType,
    this.baseVersion,
    required this.payload,
    this.beforeJson,
    required this.clientCreatedAt,
    this.clientUpdatedAt,
    this.state = OpState.pending,
    this.attempts = 0,
    this.lastErrorCode,
    this.lastErrorMessage,
    this.conflict,
    this.lastAttemptAt,
  });

  final int? seq;
  final String opId, entityType, entityId, opType, clientCreatedAt;
  final int? baseVersion;
  final Map<String, dynamic> payload;
  final Map<String, dynamic>?
  beforeJson; // snapshot to restore if the user discards an update
  final String? clientUpdatedAt, lastErrorCode, lastErrorMessage, lastAttemptAt;
  final OpState state;
  final int attempts;
  final Map<String, dynamic>? conflict;

  Map<String, dynamic> toWire() => {
    'op_id': opId,
    'entity_type': entityType,
    'entity_id': entityId,
    'op_type': opType,
    if (baseVersion != null) 'base_version': baseVersion,
    'client_created_at': clientCreatedAt,
    if (clientUpdatedAt != null) 'client_updated_at': clientUpdatedAt,
    'payload': payload,
  };

  Map<String, Object?> toRow() => {
    if (seq != null) 'seq': seq,
    'op_id': opId,
    'idempotency_key': opId,
    'entity_type': entityType,
    'entity_id': entityId,
    'op_type': opType,
    'base_version': baseVersion,
    'payload': jsonEncode(payload),
    'before_json': beforeJson == null ? null : jsonEncode(beforeJson),
    'client_created_at': clientCreatedAt,
    'client_updated_at': clientUpdatedAt,
    'state': state.name.toUpperCase(),
    'attempts': attempts,
    'last_error_code': lastErrorCode,
    'last_error_message': lastErrorMessage,
    'conflict_json': conflict == null ? null : jsonEncode(conflict),
    'last_attempt_at': lastAttemptAt,
  };

  factory OutboxOp.fromRow(Map<String, Object?> r) => OutboxOp(
    seq: r['seq'] as int?,
    opId: r['op_id']! as String,
    entityType: r['entity_type']! as String,
    entityId: r['entity_id']! as String,
    opType: r['op_type']! as String,
    baseVersion: r['base_version'] as int?,
    payload: jsonDecode(r['payload']! as String) as Map<String, dynamic>,
    beforeJson: r['before_json'] == null
        ? null
        : jsonDecode(r['before_json']! as String) as Map<String, dynamic>,
    clientCreatedAt: r['client_created_at']! as String,
    clientUpdatedAt: r['client_updated_at'] as String?,
    state: opStateFrom(r['state']! as String),
    attempts: (r['attempts'] as int?) ?? 0,
    lastErrorCode: r['last_error_code'] as String?,
    lastErrorMessage: r['last_error_message'] as String?,
    conflict: r['conflict_json'] == null
        ? null
        : jsonDecode(r['conflict_json']! as String) as Map<String, dynamic>,
    lastAttemptAt: r['last_attempt_at'] as String?,
  );
}
