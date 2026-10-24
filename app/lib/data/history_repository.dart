import 'package:drift/drift.dart';

import '../core/day.dart';
import '../domain/enums.dart';
import 'database.dart';

typedef PaidSession = ({Session session, String tableLabel, Payment payment});
typedef WalkInSale = ({Sale sale, Payment payment});
typedef UnpaidBill = ({Session session, String tableLabel});

/// Read-only lists for the History screen.
class HistoryRepository {
  HistoryRepository(this.db);

  final AppDatabase db;

  /// Table bills paid on [day], newest first.
  Stream<List<PaidSession>> watchPaidSessions(DateTime day) {
    final query = db.select(db.payments).join([
      innerJoin(db.sessions, db.sessions.id.equalsExp(db.payments.sessionId)),
      innerJoin(db.poolTables, db.poolTables.id.equalsExp(db.sessions.tableId)),
    ])
      ..where(_paidOn(day))
      ..orderBy([OrderingTerm.desc(db.payments.paidAt)]);

    return query.watch().map((rows) => [
          for (final r in rows)
            (
              session: r.readTable(db.sessions),
              tableLabel: r.readTable(db.poolTables).label,
              payment: r.readTable(db.payments),
            ),
        ]);
  }

  /// Walk-in sales paid on [day], newest first (voided ones included).
  Stream<List<WalkInSale>> watchWalkInSales(DateTime day) {
    final query = db.select(db.payments).join([
      innerJoin(db.sales, db.sales.id.equalsExp(db.payments.saleId)),
    ])
      ..where(_paidOn(day))
      ..orderBy([OrderingTerm.desc(db.payments.paidAt)]);

    return query.watch().map((rows) => [
          for (final r in rows) (sale: r.readTable(db.sales), payment: r.readTable(db.payments)),
        ]);
  }

  /// Bills where the customer left without paying and that are not written off yet.
  Stream<List<UnpaidBill>> watchUnpaid() {
    final query = db.select(db.sessions).join([
      innerJoin(db.poolTables, db.poolTables.id.equalsExp(db.sessions.tableId)),
      leftOuterJoin(
        db.voidLogs,
        db.voidLogs.refId.equalsExp(db.sessions.id) & db.voidLogs.refType.equals(voidRefUnpaid),
      ),
    ])
      ..where(db.sessions.status.equalsValue(SessionStatus.unpaid) & db.voidLogs.id.isNull())
      ..orderBy([OrderingTerm.desc(db.sessions.endedAt)]);

    return query.watch().map((rows) => [
          for (final r in rows)
            (session: r.readTable(db.sessions), tableLabel: r.readTable(db.poolTables).label),
        ]);
  }

  Stream<List<VoidLog>> watchVoids() {
    return (db.select(db.voidLogs)
          ..where((v) => v.deletedAt.isNull())
          ..orderBy([(v) => OrderingTerm.desc(v.at)]))
        .watch();
  }

  Expression<bool> _paidOn(DateTime day) {
    return db.payments.paidAt.isBiggerOrEqualValue(startOfDay(day)) &
        db.payments.paidAt.isSmallerThanValue(startOfNextDay(day)) &
        db.payments.deletedAt.isNull();
  }
}
