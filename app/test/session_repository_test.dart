import 'package:billiards_pos/data/database.dart';
import 'package:billiards_pos/data/session_repository.dart';
import 'package:billiards_pos/domain/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SessionRepository repo;
  final t0 = DateTime(2026, 1, 1, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.init();
    repo = SessionRepository(db);
  });

  tearDown(() => db.close());

  Future<PoolTable> firstTable() async =>
      (await db.select(db.poolTables).get()).first;

  test('seeds eight tables, five rates and four games', () async {
    expect((await db.select(db.poolTables).get()).length, 8);
    expect((await db.select(db.timeRates).get()).length, 5);
    expect((await db.select(db.gameTypes).get()).length, 4);
  });

  test('time session: start, extend, end, pay', () async {
    final table = await firstTable();
    final id = await repo.startTimeSession(
        tableId: table.id, minutes: 30, price: 50, now: t0);

    var s = await (db.select(db.sessions)..where((x) => x.id.equals(id))).getSingle();
    expect(s.status, SessionStatus.running);
    expect(s.total, 50);
    expect(s.endsAt, t0.add(const Duration(minutes: 30)));

    await repo.extend(sessionId: id, minutes: 60, amount: 100, now: t0);
    s = await (db.select(db.sessions)..where((x) => x.id.equals(id))).getSingle();
    expect(s.total, 150);
    expect(s.endsAt, t0.add(const Duration(minutes: 90)));

    await repo.endTable(sessionId: id, now: t0.add(const Duration(minutes: 40)));
    s = await (db.select(db.sessions)..where((x) => x.id.equals(id))).getSingle();
    expect(s.status, SessionStatus.waitingToPay);

    final change = await repo.pay(sessionId: id, cashReceived: 200, now: t0);
    expect(change, 50);
    s = await (db.select(db.sessions)..where((x) => x.id.equals(id))).getSingle();
    expect(s.status, SessionStatus.paid);
    expect((await db.select(db.payments).get()).single.amount, 150);
  });

  test('a table cannot start a second open session', () async {
    final table = await firstTable();
    await repo.startTimeSession(tableId: table.id, minutes: 30, price: 50, now: t0);
    expect(
      () => repo.startTimeSession(tableId: table.id, minutes: 30, price: 50, now: t0),
      throwsStateError,
    );
  });

  test('cannot pay before ending, or with short cash', () async {
    final table = await firstTable();
    final id = await repo.startTimeSession(
        tableId: table.id, minutes: 30, price: 50, now: t0);
    expect(() => repo.pay(sessionId: id, cashReceived: 50, now: t0), throwsStateError);

    await repo.endTable(sessionId: id, now: t0);
    expect(() => repo.pay(sessionId: id, cashReceived: 10, now: t0), throwsArgumentError);
  });

  group('game mode', () {
    Future<String> gameId(String name) async => (await (db.select(db.gameTypes)
              ..where((g) => g.name.equals(name)))
            .getSingle())
        .id;

    test('owed amount builds up game by game and merges same-price lines', () async {
      final table = await firstTable();
      final id = await repo.startGameSession(tableId: table.id, now: t0);
      expect((await repo.watchSession(id).first)!.total, 0);

      final ten = await gameId('10 balls');
      final poker = await gameId('Poker');
      await repo.addGame(sessionId: id, gameTypeId: ten, now: t0);
      await repo.addGame(sessionId: id, gameTypeId: ten, now: t0);
      await repo.addGame(sessionId: id, gameTypeId: poker, now: t0);

      final session = (await repo.watchSession(id).first)!;
      expect(session.mode, PlayMode.game);
      expect(session.endsAt, isNull);
      expect(session.total, 15 * 2 + 20);

      final lines = await repo.watchSessionGames(id).first;
      expect(lines.length, 2);
      expect(lines.firstWhere((l) => l.gameTypeId == ten).qty, 2);
    });

    test('a price change mid-session keeps old games at the old price', () async {
      final table = await firstTable();
      final id = await repo.startGameSession(tableId: table.id, now: t0);
      final ten = await gameId('10 balls');
      await repo.addGame(sessionId: id, gameTypeId: ten, now: t0);

      await (db.update(db.gameTypes)..where((g) => g.id.equals(ten)))
          .write(const GameTypesCompanion(pricePerGame: Value(30)));
      await repo.addGame(sessionId: id, gameTypeId: ten, now: t0);

      expect((await repo.watchSession(id).first)!.total, 15 + 30);
      expect((await repo.watchSessionGames(id).first).length, 2);
    });

    test('removing a game lowers the bill and is audited', () async {
      final table = await firstTable();
      final id = await repo.startGameSession(tableId: table.id, now: t0);
      final ten = await gameId('10 balls');
      await repo.addGame(sessionId: id, gameTypeId: ten, now: t0);
      await repo.addGame(sessionId: id, gameTypeId: ten, now: t0);

      final line = (await repo.watchSessionGames(id).first).single;
      await repo.removeGame(sessionId: id, sessionGameId: line.id, now: t0);
      expect((await repo.watchSession(id).first)!.total, 15);

      await repo.removeGame(sessionId: id, sessionGameId: line.id, now: t0);
      expect((await repo.watchSession(id).first)!.total, 0);
      expect(await repo.watchSessionGames(id).first, isEmpty);
      expect((await db.select(db.auditLogs).get()).length, 2);
    });

    test('games can only change while running; ending then paying works', () async {
      final table = await firstTable();
      final id = await repo.startGameSession(tableId: table.id, now: t0);
      final ten = await gameId('10 balls');
      await repo.addGame(sessionId: id, gameTypeId: ten, now: t0);
      await repo.endTable(sessionId: id, now: t0);

      expect(() => repo.addGame(sessionId: id, gameTypeId: ten, now: t0), throwsStateError);
      expect(await repo.pay(sessionId: id, cashReceived: 20, now: t0), 5);
    });

    test('cannot add games to a Time session', () async {
      final table = await firstTable();
      final id = await repo.startTimeSession(
          tableId: table.id, minutes: 30, price: 50, now: t0);
      expect(
        () => repo.addGame(sessionId: id, gameTypeId: 'x', now: t0),
        throwsStateError,
      );
    });
  });

  group('race mode', () {
    test('bills the table fee only and keeps the bet total for reference', () async {
      final table = await firstTable();
      final id = await repo.startRaceSession(
        tableId: table.id,
        raceTo: 5,
        betTotal: 1100,
        tableFee: 100,
        now: t0,
      );

      final session = (await repo.watchSession(id).first)!;
      expect(session.mode, PlayMode.race);
      expect(session.total, 100);
      expect(session.endsAt, isNull);

      final race = (await repo.watchRaceDetail(id).first)!;
      expect(race.raceTo, 5);
      expect(race.betTotal, 1100);
      expect(race.tableFee, 100);
    });

    test('an optional time limit sets an end time', () async {
      final table = await firstTable();
      final id = await repo.startRaceSession(
        tableId: table.id,
        raceTo: 3,
        betTotal: 150,
        tableFee: 50,
        minutes: 45,
        now: t0,
      );
      expect((await repo.watchSession(id).first)!.endsAt,
          t0.add(const Duration(minutes: 45)));
    });

    test('rejects a table fee bigger than the race total', () async {
      final table = await firstTable();
      expect(
        () => repo.startRaceSession(
            tableId: table.id, raceTo: 5, betTotal: 100, tableFee: 200, now: t0),
        throwsArgumentError,
      );
    });

    test('end then pay the table fee', () async {
      final table = await firstTable();
      final id = await repo.startRaceSession(
          tableId: table.id, raceTo: 5, betTotal: 1100, tableFee: 100, now: t0);
      await repo.endTable(sessionId: id, now: t0);
      expect(await repo.pay(sessionId: id, cashReceived: 100, now: t0), 0);
      expect((await db.select(db.payments).get()).single.amount, 100);
    });

    test('cannot extend a race', () async {
      final table = await firstTable();
      final id = await repo.startRaceSession(
          tableId: table.id, raceTo: 5, betTotal: 1100, tableFee: 100, now: t0);
      expect(
        () => repo.extend(sessionId: id, minutes: 30, amount: 50, now: t0),
        throwsStateError,
      );
    });
  });

  test('paid table becomes free again', () async {
    final table = await firstTable();
    final id = await repo.startTimeSession(
        tableId: table.id, minutes: 30, price: 50, now: t0);
    await repo.endTable(sessionId: id, now: t0);
    await repo.pay(sessionId: id, cashReceived: 50, now: t0);

    final rows = await repo.watchTables().first;
    expect(rows.every((r) => r.session == null), isTrue);
  });
}
