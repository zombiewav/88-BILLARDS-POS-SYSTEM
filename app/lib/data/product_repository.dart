import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'database.dart';
import 'stock.dart';

/// Products and every stock change that is not a sale.
class ProductRepository {
  ProductRepository(this.db);

  final AppDatabase db;

  /// Active and hidden products alike (the Inventory screen manages both).
  Stream<List<Product>> watchProducts() {
    return (db.select(db.products)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.category), (p) => OrderingTerm.asc(p.name)]))
        .watch();
  }

  /// Newest first.
  Stream<List<StockMovement>> watchMovements({int limit = 200}) {
    return (db.select(db.stockMovements)
          ..orderBy([(m) => OrderingTerm.desc(m.createdAt)])
          ..limit(limit))
        .watch();
  }

  Future<String> createProduct({
    required String name,
    required String category,
    required int price,
    int? costPrice,
    String? imagePath,
    int openingStock = 0,
    int lowStockLevel = 0,
    required DateTime now,
  }) {
    _validate(name: name, price: price, costPrice: costPrice, lowStockLevel: lowStockLevel);
    if (openingStock < 0) throw ArgumentError('Stock cannot be negative');

    return db.transaction(() async {
      final id = newId();
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: name.trim(),
            price: price,
            category: Value(category.trim()),
            costPrice: Value(costPrice),
            imagePath: Value(imagePath),
            lowStockLevel: Value(lowStockLevel),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      if (openingStock > 0) {
        await applyStockMovement(db,
            productId: id,
            delta: openingStock,
            reason: StockReason.stockIn,
            note: 'Opening stock',
            now: now);
      }
      return id;
    });
  }

  /// Replaces the product's details. Stock is untouched; it only moves through
  /// [stockIn], [adjustToCount], [writeOff] and sales.
  Future<void> updateProduct({
    required String id,
    required String name,
    required String category,
    required int price,
    int? costPrice,
    String? imagePath,
    required int lowStockLevel,
    required bool active,
    required DateTime now,
  }) async {
    _validate(name: name, price: price, costPrice: costPrice, lowStockLevel: lowStockLevel);
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(ProductsCompanion(
      name: Value(name.trim()),
      category: Value(category.trim()),
      price: Value(price),
      costPrice: Value(costPrice),
      imagePath: Value(imagePath),
      lowStockLevel: Value(lowStockLevel),
      active: Value(active),
      updatedAt: Value(now),
      synced: const Value(false),
    ));
  }

  Future<void> stockIn({
    required String productId,
    required int qty,
    String? note,
    required DateTime now,
  }) {
    if (qty <= 0) throw ArgumentError('Quantity must be at least 1');
    return db.transaction(() => applyStockMovement(db,
        productId: productId,
        delta: qty,
        reason: StockReason.stockIn,
        note: _clean(note),
        now: now));
  }

  /// Sets stock to a counted number (reason: adjustment). No-op if unchanged.
  Future<void> adjustToCount({
    required String productId,
    required int counted,
    String? note,
    required DateTime now,
  }) {
    if (counted < 0) throw ArgumentError('Count cannot be negative');
    return db.transaction(() async {
      final product =
          await (db.select(db.products)..where((p) => p.id.equals(productId))).getSingle();
      final delta = counted - product.stock;
      if (delta == 0) return;
      await applyStockMovement(db,
          productId: productId,
          delta: delta,
          reason: StockReason.adjustment,
          note: _clean(note),
          now: now);
    });
  }

  /// Removes stock that was damaged or lost.
  Future<void> writeOff({
    required String productId,
    required int qty,
    String? note,
    required DateTime now,
  }) {
    if (qty <= 0) throw ArgumentError('Quantity must be at least 1');
    return db.transaction(() => applyStockMovement(db,
        productId: productId,
        delta: -qty,
        reason: StockReason.damaged,
        note: _clean(note),
        now: now));
  }

  void _validate({
    required String name,
    required int price,
    int? costPrice,
    required int lowStockLevel,
  }) {
    if (name.trim().isEmpty) throw ArgumentError('Name is required');
    if (price < 0) throw ArgumentError('Price cannot be negative');
    if (costPrice != null && costPrice < 0) throw ArgumentError('Cost cannot be negative');
    if (lowStockLevel < 0) throw ArgumentError('Low-stock level cannot be negative');
  }

  String? _clean(String? note) {
    final trimmed = note?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
