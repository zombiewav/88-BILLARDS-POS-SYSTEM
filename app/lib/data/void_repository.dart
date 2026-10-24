import 'package:drift/drift.dart';

import '../domain/billing.dart';
import '../domain/enums.dart';
import 'audit.dart';
import 'database.dart';
import 'session_repository.dart';
import 'stock.dart';

/// One refundable line of a paid transaction: the table time, or a benta item.
class VoidableLine {
  const VoidableLine({
    required this.key,
    required this.label,
    required this.amount,
    required this.isTable,
    required this.voided,
  });

  /// `table` for the table-time line, otherwise the sale item's id.
  final String key;
  final String label;
  final int amount;
  final bool isTable;
  final bool voided;
}

/// Corrections that never delete anything: voids, unpaid bills and write-offs.
/// Each one needs a typed reason and leaves a void-log row and an audit row.
///
/// Voids of paid lines (`paid_table`, `paid_item`) refund money already counted
/// as income, so the daily report subtracts them. Item voids on an open bill and
/// write-offs never reached income, so they are only listed.
class VoidRepository {
  VoidRepository(this.db);

  final AppDatabase db;

  static const tableLineKey = 'table';

  /// The lines of a paid table bill, with which ones are already refunded.
  Future<List<VoidableLine>> linesForSession(String sessionId) async {
    final session = await _load(sessionId);
    final items = await _paidItems(
      db.sales.sessionId.equals(sessionId) & db.sales.status.equals(saleCompleted),
    );
    final itemTotal = items.fold<int>(0, (sum, i) => sum + i.amount);
    final voided = await _voidedRefs(sessionId, items.map((i) => i.id));

    final tableLabel = switch (session.mode) {
      PlayMode.time => 'Table time',
      PlayMode.game => 'Games',
      PlayMode.race => 'Race table fee',
    };
    final tableAmount = session.total - itemTotal;

    return [
      if (tableAmount > 0)
        VoidableLine(
          key: tableLineKey,
          label: tableLabel,
          amount: tableAmount,
          isTable: true,
          voided: voided.contains(sessionId),
        ),
      for (final i in items)
        VoidableLine(
          key: i.id,
          label: '${i.name} × ${i.qty}',
          amount: i.amount,
          isTable: false,
          voided: voided.contains(i.id),
        ),
    ];
  }

  /// The items of a paid walk-in sale.
  Future<List<VoidableLine>> linesForSale(String saleId) async {
    final items = await _paidItems(db.sales.id.equals(saleId));
    final voided = await _voidedRefs(null, items.map((i) => i.id));
    return [
      for (final i in items)
        VoidableLine(
          key: i.id,
          label: '${i.name} × ${i.qty}',
          amount: i.amount,
          isTable: false,
          voided: voided.contains(i.id),
        ),
    ];
  }

  /// Refunds the chosen lines of a paid bill ([sessionId]) or walk-in sale
  /// ([saleId]). Benta items go back to stock. [approvedBy] is the Owner whose
  /// PIN approved it. Returns the refunded amount.
  Future<int> voidLines({
    String? sessionId,
    String? saleId,
    required List<String> keys,
    required String reason,
    required String approvedBy,
    required DateTime now,
  }) {
    assert((sessionId == null) != (saleId == null), 'Pass a session or a sale');
    final why = requireReason(reason);
    if (keys.isEmpty) throw ArgumentError('Pick at least one item');

    return db.transaction(() async {
      if (sessionId != null) {
        final session = await _load(sessionId);
        if (session.status != SessionStatus.paid) {
          throw StateError('Only a paid bill can be voided');
        }
      } else {
        final sale =
            await (db.select(db.sales)..where((s) => s.id.equals(saleId!))).getSingle();
        if (sale.sessionId != null) {
          throw StateError('Void this from its table bill');
        }
      }

      final lines = sessionId != null
          ? await linesForSession(sessionId)
          : await linesForSale(saleId!);
      final chosen = [
        for (final k in keys.toSet())
          lines.firstWhere(
            (l) => l.key == k,
            orElse: () => throw StateError('That item is not on this transaction'),
          ),
      ];
      if (chosen.any((l) => l.voided)) throw StateError('That item is already voided');

      var refunded = 0;
      for (final line in chosen) {
        refunded += line.amount;
        if (line.isTable) {
          await _logVoid(voidRefPaidTable, sessionId!, why, line.amount, approvedBy, now);
          continue;
        }
        final item =
            await (db.select(db.saleItems)..where((i) => i.id.equals(line.key))).getSingle();
        await applyStockMovement(db,
            productId: item.productId,
            delta: item.qty,
            reason: StockReason.voidReturn,
            ref: item.saleId,
            note: why,
            now: now);
        await _logVoid(voidRefPaidItem, item.id, why, line.amount, approvedBy, now);
      }

      if (saleId != null) {
        final remaining = await linesForSale(saleId);
        if (remaining.every((l) => l.voided)) {
          await (db.update(db.sales)..where((s) => s.id.equals(saleId))).write(
            SalesCompanion(
              status: const Value(saleVoided),
              updatedAt: Value(now),
              synced: const Value(false),
            ),
          );
        }
      }
      return refunded;
    });
  }

  /// Takes one unit of a benta item off a table's open bill and returns it to stock.
  Future<void> voidBentaUnit({
    required String sessionId,
    required String productId,
    required int unitPrice,
    required String reason,
    required DateTime now,
  }) {
    final why = requireReason(reason);
    return db.transaction(() async {
      final session = await _load(sessionId);
      if (!_isOpen(session)) throw StateError('This bill is already closed');

      final rows = await (db.select(db.saleItems).join([
        innerJoin(db.sales, db.sales.id.equalsExp(db.saleItems.saleId)),
      ])
            ..where(db.sales.sessionId.equals(sessionId) &
                db.sales.status.equals(saleCompleted) &
                db.sales.deletedAt.isNull() &
                db.saleItems.productId.equals(productId) &
                db.saleItems.unitPrice.equals(unitPrice) &
                db.saleItems.deletedAt.isNull() &
                db.saleItems.qty.isBiggerThanValue(0))
            ..orderBy([OrderingTerm.desc(db.saleItems.createdAt)])
            ..limit(1))
          .get();
      if (rows.isEmpty) throw StateError('That item is not on the bill');

      final item = rows.first.readTable(db.saleItems);
      final sale = rows.first.readTable(db.sales);
      final qty = item.qty - 1;
      final saleTotal = sale.total - unitPrice;

      await (db.update(db.saleItems)..where((i) => i.id.equals(item.id))).write(
        SaleItemsCompanion(
          qty: Value(qty),
          deletedAt: Value(qty == 0 ? now : null),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await (db.update(db.sales)..where((s) => s.id.equals(sale.id))).write(
        SalesCompanion(
          total: Value(saleTotal),
          status: Value(saleTotal == 0 ? saleVoided : saleCompleted),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await applyStockMovement(db,
          productId: productId,
          delta: 1,
          reason: StockReason.voidReturn,
          ref: sale.id,
          note: why,
          now: now);
      await _logVoid(voidRefSaleItem, item.id, why, unitPrice, null, now);
      await recomputeSessionTotal(db, sessionId, now);
    });
  }

  /// Customer left without paying: the table is freed and the bill goes to the Unpaid list.
  Future<void> markUnpaid({
    required String sessionId,
    required String reason,
    required DateTime now,
  }) {
    final why = requireReason(reason);
    return db.transaction(() async {
      final session = await _load(sessionId);
      if (session.status != SessionStatus.waitingToPay) {
        throw StateError('End the table before marking it unpaid');
      }
      await (db.update(db.sessions)..where((s) => s.id.equals(sessionId))).write(
        SessionsCompanion(
          status: const Value(SessionStatus.unpaid),
          note: Value(why),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await writeAudit(db,
          action: 'marked_unpaid',
          entity: 'session:$sessionId',
          newValue: '${session.total}: $why',
          now: now);
    });
  }

  /// The customer came back and paid an unpaid bill. Returns the change.
  Future<int> settleUnpaid({
    required String sessionId,
    required int cashReceived,
    required DateTime now,
  }) {
    return db.transaction(() async {
      final session = await _load(sessionId);
      if (session.status != SessionStatus.unpaid) {
        throw StateError('This bill is not on the Unpaid list');
      }
      if (await _hasVoid(voidRefUnpaid, sessionId)) {
        throw StateError('This bill was already written off');
      }
      final change = changeDue(total: session.total, cashReceived: cashReceived);

      await db.into(db.payments).insert(PaymentsCompanion.insert(
            sessionId: Value(sessionId),
            amount: session.total,
            cashReceived: cashReceived,
            changeGiven: change,
            paidAt: now,
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await (db.update(db.sessions)..where((s) => s.id.equals(sessionId))).write(
        SessionsCompanion(
          status: const Value(SessionStatus.paid),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await writeAudit(db,
          action: 'unpaid_settled',
          entity: 'session:$sessionId',
          newValue: '${session.total}',
          now: now);
      return change;
    });
  }

  /// Gives up on an unpaid bill. It stays in the database and the void log.
  Future<void> writeOffUnpaid({
    required String sessionId,
    required String reason,
    required DateTime now,
  }) {
    final why = requireReason(reason);
    return db.transaction(() async {
      final session = await _load(sessionId);
      if (session.status != SessionStatus.unpaid) {
        throw StateError('This bill is not on the Unpaid list');
      }
      if (await _hasVoid(voidRefUnpaid, sessionId)) {
        throw StateError('This bill was already written off');
      }
      await _logVoid(voidRefUnpaid, sessionId, why, session.total, null, now);
    });
  }

  bool _isOpen(Session s) =>
      s.status == SessionStatus.running || s.status == SessionStatus.waitingToPay;

  Future<Session> _load(String id) {
    return (db.select(db.sessions)..where((s) => s.id.equals(id))).getSingle();
  }

  Future<bool> _hasVoid(String refType, String refId) async {
    final found = await (db.select(db.voidLogs)
          ..where((v) => v.refType.equals(refType) & v.refId.equals(refId))
          ..limit(1))
        .get();
    return found.isNotEmpty;
  }

  /// Ids (session or sale item) that already have a paid void.
  Future<Set<String>> _voidedRefs(String? sessionId, Iterable<String> itemIds) async {
    final ids = [?sessionId, ...itemIds];
    if (ids.isEmpty) return {};
    final logs = await (db.select(db.voidLogs)
          ..where((v) => v.refId.isIn(ids) & v.refType.isIn(incomeVoidKinds)))
        .get();
    return {for (final v in logs) v.refId};
  }

  /// Live benta items matching [where] (a condition on `sales`), with product names.
  Future<List<({String id, String saleId, String name, int qty, int amount})>> _paidItems(
      Expression<bool> where) async {
    final rows = await (db.select(db.saleItems).join([
      innerJoin(db.sales, db.sales.id.equalsExp(db.saleItems.saleId)),
      innerJoin(db.products, db.products.id.equalsExp(db.saleItems.productId)),
    ])
          ..where(where & db.saleItems.deletedAt.isNull() & db.saleItems.qty.isBiggerThanValue(0))
          ..orderBy([OrderingTerm.asc(db.saleItems.createdAt)]))
        .get();
    return [
      for (final r in rows)
        (
          id: r.readTable(db.saleItems).id,
          saleId: r.readTable(db.saleItems).saleId,
          name: r.readTable(db.products).name,
          qty: r.readTable(db.saleItems).qty,
          amount: r.readTable(db.saleItems).qty * r.readTable(db.saleItems).unitPrice,
        ),
    ];
  }

  Future<void> _logVoid(String refType, String refId, String reason, int amount,
      String? approvedBy, DateTime now) async {
    await db.into(db.voidLogs).insert(VoidLogsCompanion.insert(
          refType: refType,
          refId: refId,
          reason: reason,
          amount: amount,
          at: now,
          byName: Value(DeviceContext.staffName),
          approvedBy: Value(approvedBy),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
    await writeAudit(db,
        action: 'void_$refType',
        entity: '$refType:$refId',
        newValue: '$amount: $reason${approvedBy == null ? '' : ' (approved by $approvedBy)'}',
        now: now);
  }
}
