import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config.dart';
import 'data/complimentary_repository.dart';
import 'data/database.dart';
import 'data/expense_repository.dart';
import 'data/history_repository.dart';
import 'data/pricing_repository.dart';
import 'data/product_repository.dart';
import 'data/report_repository.dart';
import 'data/sale_repository.dart';
import 'data/session_repository.dart';
import 'data/settings_repository.dart';
import 'data/staff_repository.dart';
import 'data/table_repository.dart';
import 'data/void_repository.dart';

/// Overridden in main() with the opened database.
final databaseProvider = Provider<AppDatabase>((ref) => throw UnimplementedError());

/// The one source of "now". Tests and screens read time through this.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final _tickProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  final clock = ref.watch(clockProvider);
  yield clock();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => clock());
});

/// Current time, refreshed every second so countdowns tick.
final currentTimeProvider = Provider.autoDispose<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  return ref.watch(_tickProvider).valueOrNull ?? clock();
});

final _minuteTickProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  final clock = ref.watch(clockProvider);
  var last = clock();
  yield last;
  await for (final _ in Stream<void>.periodic(const Duration(seconds: 1))) {
    final now = clock();
    if (now.minute != last.minute || now.day != last.day) {
      last = now;
      yield now;
    }
  }
});

/// Current time, refreshed once a minute. Use this unless seconds are shown:
/// it rebuilds a screen 60 times less than [currentTimeProvider].
final currentMinuteProvider = Provider.autoDispose<DateTime>((ref) {
  final clock = ref.watch(clockProvider);
  return ref.watch(_minuteTickProvider).valueOrNull ?? clock();
});

final settingsRepositoryProvider =
    Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));

final settingsProvider = StreamProvider<Map<String, String>>(
    (ref) => ref.watch(settingsRepositoryProvider).watchAll());

String _setting(Ref ref, String key, String fallback) =>
    ref.watch(settingsProvider).valueOrNull?[key] ?? fallback;

bool _flag(Ref ref, String key) => _setting(ref, key, 'true') == 'true';

final businessNameProvider = Provider((ref) => _setting(ref, kBusinessName, '88 Billiards'));
final branchNameProvider = Provider((ref) => _setting(ref, kBranchName, 'Main Branch'));

/// Minutes before a Time session ends that the table turns "Ending soon".
final alertMinutesProvider = Provider<int>(
    (ref) => int.tryParse(_setting(ref, kAlertMinutes, '')) ?? defaultAlertMinutes);

final soundVibrationProvider = Provider((ref) => _flag(ref, kSoundVibration));
final lowStockWarningProvider = Provider((ref) => _flag(ref, kLowStockWarning));

final syncMinutesProvider =
    Provider<int>((ref) => int.tryParse(_setting(ref, kSyncMinutes, '')) ?? 5);

final themeModeProvider = Provider<ThemeMode>((ref) => switch (_setting(ref, kThemeMode, 'auto')) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    });

/// When the last sync with the server finished (never, until sync is built).
final lastSyncProvider = Provider<DateTime?>(
    (ref) => DateTime.tryParse(_setting(ref, kLastSync, '')));

final sessionRepositoryProvider =
    Provider((ref) => SessionRepository(ref.watch(databaseProvider)));

final tablesProvider = StreamProvider<List<TableWithSession>>(
    (ref) => ref.watch(sessionRepositoryProvider).watchTables());

final sessionProvider = StreamProvider.family<Session?, String>(
    (ref, id) => ref.watch(sessionRepositoryProvider).watchSession(id));

final extensionsProvider = StreamProvider.family<List<SessionExtension>, String>(
    (ref, id) => ref.watch(sessionRepositoryProvider).watchExtensions(id));

final timeRatesProvider = StreamProvider<List<TimeRate>>(
    (ref) => ref.watch(sessionRepositoryProvider).watchTimeRates());

final gameTypesProvider = StreamProvider<List<GameType>>(
    (ref) => ref.watch(sessionRepositoryProvider).watchGameTypes());

final sessionGamesProvider = StreamProvider.family<List<SessionGame>, String>(
    (ref, id) => ref.watch(sessionRepositoryProvider).watchSessionGames(id));

final productRepositoryProvider =
    Provider((ref) => ProductRepository(ref.watch(databaseProvider)));

final saleRepositoryProvider =
    Provider((ref) => SaleRepository(ref.watch(databaseProvider)));

final floorZonesProvider = StreamProvider<List<FloorZone>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.floorZones)
        ..where((z) => z.deletedAt.isNull())
        ..orderBy([(z) => OrderingTerm.asc(z.createdAt)]))
      .watch();
});

final tableRepositoryProvider =
    Provider((ref) => TableRepository(ref.watch(databaseProvider)));

final pricingRepositoryProvider =
    Provider((ref) => PricingRepository(ref.watch(databaseProvider)));

/// Rows saved on this tablet that the server has not received yet.
final unsyncedCountProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(dataChangedProvider);
  final db = ref.watch(databaseProvider);
  var total = 0;
  for (final table in [
    'sessions',
    'sales',
    'payments',
    'expenses',
    'stock_movements',
    'void_logs',
    'products',
  ]) {
    final row = await db.customSelect('SELECT COUNT(*) AS n FROM $table WHERE synced = 0').getSingle();
    total += row.read<int>('n');
  }
  return total;
});

final staffRepositoryProvider =
    Provider((ref) => StaffRepository(ref.watch(databaseProvider)));

final reportRepositoryProvider =
    Provider((ref) => ReportRepository(ref.watch(databaseProvider)));

/// Fires whenever anything in the database changes, so reports stay current.
final dataChangedProvider = StreamProvider<void>(
    (ref) => ref.watch(databaseProvider).tableUpdates().map((_) {}));

final periodReportProvider =
    FutureProvider.autoDispose.family<PeriodReport, (ReportPeriod, DateTime)>((ref, key) {
  ref.watch(dataChangedProvider);
  return ref.watch(reportRepositoryProvider).forPeriod(key.$1, key.$2);
});

/// Net profit of the 7 days ending on the given day, oldest first.
final netSeriesProvider = FutureProvider.autoDispose.family<List<int>, DateTime>((ref, lastDay) {
  ref.watch(dataChangedProvider);
  return ref.watch(reportRepositoryProvider).netSeries(lastDay);
});

final staffListProvider = StreamProvider<List<StaffMember>>(
    (ref) => ref.watch(staffRepositoryProvider).watchAll());

/// Lines of a paid table bill that can be refunded (reload after a void).
final sessionLinesProvider = FutureProvider.autoDispose.family<List<VoidableLine>, String>((ref, id) {
  ref.watch(voidsProvider); // reload whenever a void is logged
  return ref.watch(voidRepositoryProvider).linesForSession(id);
});

final saleLinesProvider = FutureProvider.autoDispose.family<List<VoidableLine>, String>((ref, id) {
  ref.watch(voidsProvider);
  return ref.watch(voidRepositoryProvider).linesForSale(id);
});

final expenseRepositoryProvider =
    Provider((ref) => ExpenseRepository(ref.watch(databaseProvider)));

final complimentaryRepositoryProvider =
    Provider((ref) => ComplimentaryRepository(ref.watch(databaseProvider)));

final voidRepositoryProvider =
    Provider((ref) => VoidRepository(ref.watch(databaseProvider)));

final historyRepositoryProvider =
    Provider((ref) => HistoryRepository(ref.watch(databaseProvider)));

final expensesForDayProvider = StreamProvider.family<List<Expense>, DateTime>(
    (ref, day) => ref.watch(expenseRepositoryProvider).watchDay(day));

final expensesRangeProvider = StreamProvider.family<List<Expense>, (DateTime, DateTime)>(
    (ref, range) => ref.watch(expenseRepositoryProvider).watchRange(range.$1, range.$2));

final complimentaryProvider = StreamProvider.family<List<ComplimentaryLine>, String>(
    (ref, id) => ref.watch(complimentaryRepositoryProvider).watch(id));

final paidSessionsProvider = StreamProvider.family<List<PaidSession>, DateTime>(
    (ref, day) => ref.watch(historyRepositoryProvider).watchPaidSessions(day));

final walkInSalesProvider = StreamProvider.family<List<WalkInSale>, DateTime>(
    (ref, day) => ref.watch(historyRepositoryProvider).watchWalkInSales(day));

final unpaidProvider = StreamProvider<List<UnpaidBill>>(
    (ref) => ref.watch(historyRepositoryProvider).watchUnpaid());

final voidsProvider = StreamProvider<List<VoidLog>>(
    (ref) => ref.watch(historyRepositoryProvider).watchVoids());

final productsProvider =StreamProvider<List<Product>>(
    (ref) => ref.watch(productRepositoryProvider).watchProducts());

final stockMovementsProvider = StreamProvider<List<StockMovement>>(
    (ref) => ref.watch(productRepositoryProvider).watchMovements());

final sessionBentaProvider = StreamProvider.family<List<BentaLine>, String>(
    (ref, id) => ref.watch(saleRepositoryProvider).watchSessionBenta(id));

/// Products that need restocking: a low-stock level is set and stock is at or below it.
final lowStockCountProvider = Provider<int>((ref) {
  final products = ref.watch(productsProvider).valueOrNull ?? const <Product>[];
  return products.where((p) => p.active && isLowStock(p)).length;
});

bool isLowStock(Product p) => p.lowStockLevel > 0 && p.stock <= p.lowStockLevel;

final raceDetailProvider =StreamProvider.family<RaceDetail?, String>(
    (ref, id) => ref.watch(sessionRepositoryProvider).watchRaceDetail(id));
