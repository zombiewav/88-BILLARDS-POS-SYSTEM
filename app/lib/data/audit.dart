import 'package:drift/drift.dart';

import 'database.dart';

/// Appends one row to the audit log. It is append only: rows are never edited.
Future<void> writeAudit(
  AppDatabase db, {
  required String action,
  required String entity,
  String? oldValue,
  String? newValue,
  required DateTime now,
}) async {
  await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
        actor: DeviceContext.deviceId,
        action: action,
        entity: entity,
        oldValue: Value(oldValue),
        newValue: Value(newValue),
        at: now,
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
}

/// Voids, unpaid marks and deletes all need a typed reason.
String requireReason(String? reason) {
  final trimmed = reason?.trim() ?? '';
  if (trimmed.isEmpty) throw ArgumentError('A reason is required');
  return trimmed;
}
