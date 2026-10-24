import 'package:drift/drift.dart';

import '../domain/billing.dart';
import '../domain/enums.dart';
import 'database.dart';
import 'refs.dart';
import 'session_repository.dart';
import 'stock.dart';

/// One product on a table's bill, summed over every sale attached to it.
class BentaLine {
  const BentaLine(this.productId, this.name, this.qty, this.unitPrice);

  final String productId;
  final String name;
  final int qty;
  final int unitPrice;

  int get amount => qty * unitPrice;
}

/// Benta: drinks and items sold either onto a table's bill or to a walk-in.
/// A cart is a map of product id to quantity.
class SaleRepository {
  SaleRepository(this.db);

  final AppDatabase db;

  Stream<List<BentaLine>> watchSessionBenta(String sessionId) {
    final query = db.select(db.saleItems).join([
      innerJoin(db.sales, db.sales.id.equalsExp(db.saleItems.saleId)),
      innerJoin(db.products, db.products.id.equalsExp(db.saleItems.productId)),
    ])
      ..where(db.sales.sessionId.equals(sessionId) &
          db.sales.status.equals(saleCompleted) &
          db.sales.deletedAt.isNull() &
          db.saleItems.deletedAt.isNull())
      ..orderBy([OrderingTerm.asc(db.saleItems.createdAt)]);

    return query.watch().map((rows) {
      final lines = <String, BentaLine>{};
      for (final r in rows) {
        final item = r.readTable(db.saleItems);
        final name = r.readTable(db.products).name;
        final key = '${item.productId}|${item.unitPrice}';
        final old = lines[key];
        lines[key] =
            BentaLine(item.productId, name, (old?.qty ?? 0) + item.qty, item.unitPrice);
      }
      return lines.values.where((l) => l.qty > 0).toList();
    });
  }

  /// Adds the cart to an open table's bill (running or waiting to pay).
  /// It is paid together with the table.
  Future<void> addToTable({
    required String sessionId,
    required Map<String, int> cart,
    required DateTime now,
  }) {
    return db.transaction(() async {
      final session =
          await (db.select(db.sessions)..where((s) => s.id.equals(sessionId))).getSingle();
      if (session.status != SessionStatus.running &&
          session.status != SessionStatus.waitingToPay) {
        throw StateError('This table has no open bill');
      }
      await _createSale(cart: cart, sessionId: sessionId, now: now);
      await recomputeSessionTotal(db, sessionId, now);
    });
  }

  /// Sells the cart to a walk-in for cash. Returns the change to give.
  Future<int> sellStandalone({
    required Map<String, int> cart,
    required int cashReceived,
    required DateTime now,
  }) {
    return db.transaction(() async {
      final sale = await _createSale(cart: cart, now: now);
      final change = changeDue(total: sale.total, cashReceived: cashReceived);
      await db.into(db.payments).insert(PaymentsCompanion.insert(
            saleId: Value(sale.id),
            amount: sale.total,
            cashReceived: cashReceived,
            changeGiven: change,
            paidAt: now,
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      return change;
    });
  }

  /// Prices the cart at today's prices, writes the sale and its items, and
  /// takes the stock out. Everything or nothing: call inside a transaction.
  Future<({String id, int total})> _createSale({
    required Map<String, int> cart,
    String? sessionId,
    required DateTime now,
  }) async {
    final wanted = Map.of(cart)..removeWhere((_, qty) => qty <= 0);
    if (wanted.isEmpty) throw ArgumentError('The cart is empty');

    final products = await (db.select(db.products)
          ..where((p) => p.id.isIn(wanted.keys) & p.deletedAt.isNull()))
        .get();
    final byId = {for (final p in products) p.id: p};

    var total = 0;
    for (final entry in wanted.entries) {
      final product = byId[entry.key];
      if (product == null || !product.active) {
        throw StateError('A product in the cart is no longer for sale');
      }
      total += product.price * entry.value;
    }

    final saleId = newId();
    await db.into(db.sales).insert(SalesCompanion.insert(
          id: Value(saleId),
          ref: Value(await nextRef(db, now)),
          soldBy: Value(DeviceContext.staffName),
          sessionId: Value(sessionId),
          total: total,
          createdAt: Value(now),
          updatedAt: Value(now),
        ));

    for (final entry in wanted.entries) {
      final product = byId[entry.key]!;
      await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
            saleId: saleId,
            productId: product.id,
            qty: entry.value,
            unitPrice: product.price,
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await applyStockMovement(db,
          productId: product.id,
          delta: -entry.value,
          reason: StockReason.sale,
          ref: saleId,
          now: now);
    }
    return (id: saleId, total: total);
  }
}
