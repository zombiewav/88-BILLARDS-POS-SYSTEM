import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'audit.dart';
import 'database.dart';
import 'stock.dart';

class ComplimentaryLine {
  const ComplimentaryLine(this.id, this.name, this.qty, this.costAmount);

  final String id;
  final String name;
  final int qty;
  final int costAmount;
}

/// Free drinks the hall gives during a race. They are not charged to the
/// customer, they take stock out, and they are booked as an expense.
class ComplimentaryRepository {
  ComplimentaryRepository(this.db);

  final AppDatabase db;

  Stream<List<ComplimentaryLine>> watch(String sessionId) {
    final query = db.select(db.complimentaryItems).join([
      innerJoin(db.products, db.products.id.equalsExp(db.complimentaryItems.productId)),
    ])
      ..where(db.complimentaryItems.sessionId.equals(sessionId) &
          db.complimentaryItems.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(db.complimentaryItems.createdAt)]);

    return query.watch().map((rows) => [
          for (final r in rows)
            ComplimentaryLine(
              r.readTable(db.complimentaryItems).id,
              r.readTable(db.products).name,
              r.readTable(db.complimentaryItems).qty,
              r.readTable(db.complimentaryItems).costAmount,
            ),
        ]);
  }

  /// Gives [qty] of a product free to a race. The expense is the drink's cost
  /// price, or its selling price when no cost is set.
  Future<String> add({
    required String sessionId,
    required String productId,
    required int qty,
    String? note,
    required DateTime now,
  }) {
    if (qty <= 0) throw ArgumentError('Quantity must be at least 1');

    return db.transaction(() async {
      final session = await _openRace(sessionId);
      final product = await (db.select(db.products)
            ..where((p) => p.id.equals(productId) & p.deletedAt.isNull()))
          .getSingleOrNull();
      if (product == null || !product.active) {
        throw StateError('That product is no longer for sale');
      }
      final table =
          await (db.select(db.poolTables)..where((t) => t.id.equals(session.tableId))).getSingle();

      final itemId = newId();
      final cost = (product.costPrice ?? product.price) * qty;
      final cleanNote = note?.trim();

      await db.into(db.complimentaryItems).insert(ComplimentaryItemsCompanion.insert(
            id: Value(itemId),
            sessionId: sessionId,
            productId: productId,
            qty: qty,
            costAmount: cost,
            note: Value(cleanNote == null || cleanNote.isEmpty ? null : cleanNote),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await applyStockMovement(db,
          productId: productId,
          delta: -qty,
          reason: StockReason.complimentary,
          ref: itemId,
          now: now);
      await db.into(db.expenses).insert(ExpensesCompanion.insert(
            name: 'Free ${product.name} × $qty (${table.label} race)',
            amount: cost,
            category: const Value('Free drinks'),
            date: now,
            source: ExpenseSource.complimentary,
            ref: Value(itemId),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      return itemId;
    });
  }

  /// Takes a free drink back (a wrong tap): stock returns and the expense goes.
  Future<void> remove({required String itemId, required DateTime now}) {
    return db.transaction(() async {
      final item = await (db.select(db.complimentaryItems)
            ..where((c) => c.id.equals(itemId)))
          .getSingle();
      if (item.deletedAt != null) return;
      await _openRace(item.sessionId);

      await (db.update(db.complimentaryItems)..where((c) => c.id.equals(itemId))).write(
        ComplimentaryItemsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await (db.update(db.expenses)
            ..where((e) => e.ref.equals(itemId) & e.deletedAt.isNull()))
          .write(ExpensesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await applyStockMovement(db,
          productId: item.productId,
          delta: item.qty,
          reason: StockReason.voidReturn,
          ref: itemId,
          note: 'Free drink taken back',
          now: now);
      await writeAudit(db,
          action: 'complimentary_removed',
          entity: 'session:${item.sessionId}',
          oldValue: 'qty ${item.qty}, cost ${item.costAmount}',
          now: now);
    });
  }

  Future<Session> _openRace(String sessionId) async {
    final session =
        await (db.select(db.sessions)..where((s) => s.id.equals(sessionId))).getSingle();
    final open = session.status == SessionStatus.running ||
        session.status == SessionStatus.waitingToPay;
    if (session.mode != PlayMode.race || !open) {
      throw StateError('Free drinks can only be given on an open Race');
    }
    return session;
  }
}
