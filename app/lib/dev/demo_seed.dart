import '../data/database.dart';
import '../data/sale_repository.dart';
import '../data/session_repository.dart';

/// Debug only (`--dart-define=SEED_DEMO=true`): a few running tables like the design,
/// so screens can be checked without setting anything up. Never runs in a release build.
Future<void> seedDemo(AppDatabase db) async {
  final now = DateTime.now();

  final sessions = SessionRepository(db);
  final sales = SaleRepository(db);
  final tables = {for (final t in await db.select(db.poolTables).get()) t.label: t.id};
  final open = await db.select(db.sessions).get();
  if (open.isNotEmpty) return;

  DateTime ago(int minutes, [int seconds = 0]) =>
      now.subtract(Duration(minutes: minutes, seconds: seconds));

  await sessions.startTimeSession(tableId: tables['T1']!, minutes: 60, price: 100, now: ago(42));

  final t2 = await sessions.startGameSession(tableId: tables['T2']!, now: ago(22, 10));
  final games = await db.select(db.gameTypes).get();
  final ten = games.firstWhere((g) => g.name == '10 balls');
  for (var i = 0; i < 3; i++) {
    await sessions.addGame(sessionId: t2, gameTypeId: ten.id, now: ago(20 - i));
  }

  final t4 = await sessions.startTimeSession(
      tableId: tables['T4']!, minutes: 30, price: 50, now: ago(26, 40));
  final products = await db.select(db.products).get();
  Product p(String n) => products.firstWhere((x) => x.name == n);
  await sales.addToTable(sessionId: t4, cart: {p('Royal').id: 1, p('Coke').id: 2}, now: ago(20));

  final t5 = await sessions.startGameSession(tableId: tables['T5']!, now: ago(37));
  final fifteen = games.firstWhere((g) => g.name == '15 balls');
  for (var i = 0; i < 2; i++) {
    await sessions.addGame(sessionId: t5, gameTypeId: fifteen.id, now: ago(30 - i));
  }

  await sessions.startTimeSession(tableId: tables['T7']!, minutes: 120, price: 200, now: ago(72));
}
