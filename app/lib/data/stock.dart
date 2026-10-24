import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'database.dart';

/// Changes a product's stock by [delta] and writes the inventory-log row.
/// Stock never changes any other way, so the log always explains the count.
/// Call inside a transaction. Throws if the stock would go below zero.
Future<void> applyStockMovement(
  AppDatabase db, {
  required String productId,
  required int delta,
  required StockReason reason,
  required DateTime now,
  String? ref,
  String? note,
}) async {
  final product =
      await (db.select(db.products)..where((p) => p.id.equals(productId))).getSingle();
  final after = product.stock + delta;
  if (after < 0) throw StateError('Not enough stock for ${product.name}');

  await (db.update(db.products)..where((p) => p.id.equals(productId))).write(
    ProductsCompanion(
      stock: Value(after),
      updatedAt: Value(now),
      synced: const Value(false),
    ),
  );
  await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
        productId: productId,
        delta: delta,
        stockBefore: product.stock,
        stockAfter: after,
        reason: reason,
        ref: Value(ref),
        note: Value(note),
        createdAt: Value(now),
        updatedAt: Value(now),
      ));
}
