import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/enums.dart';
import 'tables.dart';

export 'tables.dart'
    show
        DeviceContext,
        newId,
        saleCompleted,
        saleVoided,
        voidRefPaidTable,
        voidRefPaidItem,
        voidRefSaleItem,
        voidRefUnpaid,
        incomeVoidKinds;

part 'database.g.dart';

const _deviceIdKey = 'device_id';

@DriftDatabase(tables: [
  PoolTables,
  FloorZones,
  TimeRates,
  GameTypes,
  Sessions,
  SessionExtensions,
  SessionGames,
  RaceDetails,
  Products,
  ComplimentaryItems,
  Sales,
  SaleItems,
  StockMovements,
  Expenses,
  Payments,
  VoidLogs,
  AuditLogs,
  StaffTable,
  AppSettings,
])
class AppDatabase extends _$AppDatabase {
  /// [executor] is only for tests. For trying the app without touching real data,
  /// run with `--dart-define=DB_NAME=scratch`.
  AppDatabase([QueryExecutor? executor])
      : super(executor ??
            driftDatabase(name: const String.fromEnvironment('DB_NAME', defaultValue: 'billiards_pos')));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(stockMovements, stockMovements.note);
          if (from < 3) await m.addColumn(expenses, expenses.ref);
          if (from < 4) {
            await m.addColumn(sessions, sessions.ref);
            await m.addColumn(sessions, sessions.openedBy);
            await m.addColumn(sales, sales.ref);
            await m.addColumn(sales, sales.soldBy);
            await m.addColumn(expenses, expenses.category);
            await m.addColumn(voidLogs, voidLogs.byName);
            await m.addColumn(voidLogs, voidLogs.approvedBy);
            await m.createTable(staffTable);
          }
          if (from < 5) {
            await m.createTable(floorZones);
            await _seedZones();
          }
        },
        onCreate: (m) async {
          await m.createAll();
          // The device id must exist before seeding so seeded rows carry it.
          final deviceId = newId();
          await into(appSettings).insert(AppSettingsCompanion.insert(
            settingKey: _deviceIdKey,
            settingValue: deviceId,
          ));
          DeviceContext.deviceId = deviceId;
          await _seedDefaults();
        },
      );

  /// Opens the database and loads the device id into [DeviceContext].
  Future<void> init() async {
    final row = await (select(appSettings)
          ..where((s) => s.settingKey.equals(_deviceIdKey)))
        .getSingleOrNull();
    if (row != null) DeviceContext.deviceId = row.settingValue;
  }

  /// The counter and the entrance, as in the design. The Owner can move or delete them.
  Future<void> _seedZones() async {
    const zones = [
      (label: 'Counter · Cashier', x: 2, y: 3, w: 3, h: 1),
      (label: 'Entrance', x: 6, y: 3, w: 2, h: 1),
    ];
    for (final z in zones) {
      await into(floorZones).insert(FloorZonesCompanion.insert(
        label: z.label,
        mapX: Value(z.x),
        mapY: Value(z.y),
        w: Value(z.w),
        h: Value(z.h),
      ));
    }
  }

  Future<void> _seedDefaults() async {
    // The floor from the design: T1 and T2 stand tall on the left, T3 to T8 in two rows.
    const floor = [
      (label: 'T1', x: 0, y: 0, w: 1, h: 2),
      (label: 'T2', x: 0, y: 3, w: 1, h: 2),
      (label: 'T3', x: 2, y: 0, w: 2, h: 1),
      (label: 'T4', x: 2, y: 2, w: 2, h: 1),
      (label: 'T5', x: 4, y: 0, w: 2, h: 1),
      (label: 'T6', x: 4, y: 2, w: 2, h: 1),
      (label: 'T7', x: 6, y: 0, w: 2, h: 1),
      (label: 'T8', x: 6, y: 2, w: 2, h: 1),
    ];
    for (final t in floor) {
      await into(poolTables).insert(PoolTablesCompanion.insert(
        label: t.label,
        mapX: Value(t.x),
        mapY: Value(t.y),
        w: Value(t.w),
        h: Value(t.h),
      ));
    }

    await _seedZones();

    const rates = {30: 50, 60: 100, 90: 150, 120: 200, 180: 300};
    for (final r in rates.entries) {
      await into(timeRates)
          .insert(TimeRatesCompanion.insert(minutes: r.key, price: r.value));
    }

    const games = {'10 balls': 15, '15 balls': 20, '20 balls': 25, 'Poker': 20};
    for (final g in games.entries) {
      await into(gameTypes).insert(
          GameTypesCompanion.insert(name: g.key, pricePerGame: g.value));
    }

    // (name, type, price, cost, stock, low-stock level)
    const items = [
      ('Royal', 'Drinks', 15, 10, 24, 5),
      ('Coke', 'Drinks', 15, 10, 24, 5),
      ('Sprite', 'Drinks', 15, 10, 12, 5),
      ('Mineral water', 'Drinks', 10, 6, 30, 5),
      ('Energy drink', 'Drinks', 25, 18, 4, 5),
      ('Chips', 'Snacks', 20, 14, 3, 5),
      ('Coffee sachet', 'Snacks', 12, 8, 40, 10),
      ('Cue chalk', 'Other', 10, 6, 15, 5),
    ];
    for (final p in items) {
      final id = newId();
      await into(products).insert(ProductsCompanion.insert(
        id: Value(id),
        name: p.$1,
        price: p.$3,
        category: Value(p.$2),
        costPrice: Value(p.$4),
        stock: Value(p.$5),
        lowStockLevel: Value(p.$6),
      ));
      await into(stockMovements).insert(StockMovementsCompanion.insert(
        productId: id,
        delta: p.$5,
        stockBefore: 0,
        stockAfter: p.$5,
        reason: StockReason.stockIn,
        note: const Value('Opening stock'),
      ));
    }
  }
}
