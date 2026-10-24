import 'package:drift/drift.dart';

import 'audit.dart';
import 'database.dart';

/// Time rates and game prices. Changes are logged (old price, new price).
/// Sessions keep the price they started with, so edits never rewrite history.
class PricingRepository {
  PricingRepository(this.db);

  final AppDatabase db;

  Future<void> setTimeRatePrice({required String id, required int price, required DateTime now}) {
    if (price < 0) throw ArgumentError('Price cannot be negative');
    return db.transaction(() async {
      final rate = await (db.select(db.timeRates)..where((r) => r.id.equals(id))).getSingle();
      if (rate.price == price) return;
      await (db.update(db.timeRates)..where((r) => r.id.equals(id))).write(TimeRatesCompanion(
        price: Value(price),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await writeAudit(db,
          action: 'time_rate_changed',
          entity: 'time_rate:${rate.minutes}min',
          oldValue: '${rate.price}',
          newValue: '$price',
          now: now);
    });
  }

  Future<void> addTimeRate({required int minutes, required int price, required DateTime now}) {
    if (minutes <= 0) throw ArgumentError('Minutes must be more than 0');
    if (price < 0) throw ArgumentError('Price cannot be negative');
    return db.transaction(() async {
      final clash = await (db.select(db.timeRates)
            ..where((r) => r.minutes.equals(minutes) & r.deletedAt.isNull()))
          .get();
      if (clash.isNotEmpty) throw StateError('There is already a $minutes minute rate');
      await db.into(db.timeRates).insert(TimeRatesCompanion.insert(
            minutes: minutes,
            price: price,
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await writeAudit(db,
          action: 'time_rate_added', entity: 'time_rate:${minutes}min', newValue: '$price', now: now);
    });
  }

  Future<void> removeTimeRate({required String id, required DateTime now}) {
    return db.transaction(() async {
      final rate = await (db.select(db.timeRates)..where((r) => r.id.equals(id))).getSingle();
      await (db.update(db.timeRates)..where((r) => r.id.equals(id))).write(TimeRatesCompanion(
        deletedAt: Value(now),
        active: const Value(false),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await writeAudit(db,
          action: 'time_rate_removed',
          entity: 'time_rate:${rate.minutes}min',
          oldValue: '${rate.price}',
          now: now);
    });
  }

  Future<void> setGamePrice({required String id, required int price, required DateTime now}) {
    if (price < 0) throw ArgumentError('Price cannot be negative');
    return db.transaction(() async {
      final game = await (db.select(db.gameTypes)..where((g) => g.id.equals(id))).getSingle();
      if (game.pricePerGame == price) return;
      await (db.update(db.gameTypes)..where((g) => g.id.equals(id))).write(GameTypesCompanion(
        pricePerGame: Value(price),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await writeAudit(db,
          action: 'game_price_changed',
          entity: 'game:${game.name}',
          oldValue: '${game.pricePerGame}',
          newValue: '$price',
          now: now);
    });
  }

  Future<void> addGame({required String name, required int price, required DateTime now}) {
    if (name.trim().isEmpty) throw ArgumentError('Name is required');
    if (price < 0) throw ArgumentError('Price cannot be negative');
    return db.transaction(() async {
      await db.into(db.gameTypes).insert(GameTypesCompanion.insert(
            name: name.trim(),
            pricePerGame: price,
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await writeAudit(db,
          action: 'game_added', entity: 'game:${name.trim()}', newValue: '$price', now: now);
    });
  }

  Future<void> removeGame({required String id, required DateTime now}) {
    return db.transaction(() async {
      final game = await (db.select(db.gameTypes)..where((g) => g.id.equals(id))).getSingle();
      await (db.update(db.gameTypes)..where((g) => g.id.equals(id))).write(GameTypesCompanion(
        deletedAt: Value(now),
        active: const Value(false),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await writeAudit(db,
          action: 'game_removed_from_menu',
          entity: 'game:${game.name}',
          oldValue: '${game.pricePerGame}',
          now: now);
    });
  }
}
