import 'package:drift/drift.dart';

import '../domain/billing.dart';
import '../domain/enums.dart';
import 'database.dart';
import 'refs.dart';

const _openStatuses = [SessionStatus.running, SessionStatus.waitingToPay];

/// Rebuilds a session's running bill from its rows: the mode total plus benta
/// from completed sales. Recomputing (never adding to the old total) means the
/// bill can't drift. Call inside a transaction after changing any of those rows.
Future<void> recomputeSessionTotal(AppDatabase db, String sessionId, DateTime now) async {
  final session =
      await (db.select(db.sessions)..where((s) => s.id.equals(sessionId))).getSingle();

  final int modeTotal;
  switch (session.mode) {
    case PlayMode.time:
      final extensions = await (db.select(db.sessionExtensions)
            ..where((e) => e.sessionId.equals(sessionId) & e.deletedAt.isNull()))
          .get();
      modeTotal = timeTotal(
        blockPrice: session.baseAmount,
        extensionAmounts: extensions.map((e) => e.amount),
      );
    case PlayMode.game:
      final lines = await (db.select(db.sessionGames)
            ..where((g) => g.sessionId.equals(sessionId) & g.deletedAt.isNull()))
          .get();
      modeTotal = gameTotal(lines.map((l) => GameLine(l.qty, l.unitPrice)));
    case PlayMode.race:
      final race = await (db.select(db.raceDetails)
            ..where((r) => r.sessionId.equals(sessionId)))
          .getSingle();
      modeTotal = raceTotal(tableFee: race.tableFee);
  }

  final sales = await (db.select(db.sales)
        ..where((s) =>
            s.sessionId.equals(sessionId) &
            s.status.equals(saleCompleted) &
            s.deletedAt.isNull()))
      .get();
  final benta = sales.fold<int>(0, (sum, s) => sum + s.total);

  await (db.update(db.sessions)..where((s) => s.id.equals(sessionId))).write(
    SessionsCompanion(
      total: Value(tableBill(modeTotal: modeTotal, bentaTotal: benta)),
      updatedAt: Value(now),
      synced: const Value(false),
    ),
  );
}

class TableWithSession {
  const TableWithSession(this.table, this.session);

  final PoolTable table;

  /// The open session (running or waiting to pay), or null when the table is free.
  final Session? session;
}

class SessionRepository {
  SessionRepository(this.db);

  final AppDatabase db;

  Stream<List<TableWithSession>> watchTables() {
    final query = db.select(db.poolTables).join([
      leftOuterJoin(
        db.sessions,
        db.sessions.tableId.equalsExp(db.poolTables.id) &
            db.sessions.status.isInValues(_openStatuses) &
            db.sessions.deletedAt.isNull(),
      ),
    ])
      ..where(db.poolTables.active.equals(true) & db.poolTables.deletedAt.isNull())
      ..orderBy([
        OrderingTerm.asc(db.poolTables.mapY),
        OrderingTerm.asc(db.poolTables.mapX),
        OrderingTerm.asc(db.poolTables.label),
      ]);

    return query.watch().map((rows) {
      final list = [
        for (final r in rows)
          TableWithSession(r.readTable(db.poolTables), r.readTableOrNull(db.sessions)),
      ];
      // T1, T2 ... T10 in number order (plain text order would put T10 before T2).
      list.sort((a, b) {
        final byLength = a.table.label.length.compareTo(b.table.label.length);
        return byLength != 0 ? byLength : a.table.label.compareTo(b.table.label);
      });
      return list;
    });
  }

  Stream<Session?> watchSession(String id) {
    return (db.select(db.sessions)..where((s) => s.id.equals(id))).watchSingleOrNull();
  }

  Stream<List<SessionExtension>> watchExtensions(String sessionId) {
    return (db.select(db.sessionExtensions)
          ..where((e) => e.sessionId.equals(sessionId))
          ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
        .watch();
  }

  Stream<List<TimeRate>> watchTimeRates() {
    return (db.select(db.timeRates)
          ..where((r) => r.active.equals(true) & r.deletedAt.isNull())
          ..orderBy([(r) => OrderingTerm.asc(r.minutes)]))
        .watch();
  }

  Stream<List<GameType>> watchGameTypes() {
    return (db.select(db.gameTypes)
          ..where((g) => g.active.equals(true) & g.deletedAt.isNull())
          ..orderBy([
            (g) => OrderingTerm.asc(g.createdAt),
            (g) => OrderingTerm.asc(g.name),
          ]))
        .watch();
  }

  Stream<List<SessionGame>> watchSessionGames(String sessionId) {
    return (db.select(db.sessionGames)
          ..where((g) => g.sessionId.equals(sessionId) & g.deletedAt.isNull())
          ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
        .watch();
  }

  Stream<RaceDetail?> watchRaceDetail(String sessionId) {
    return (db.select(db.raceDetails)..where((r) => r.sessionId.equals(sessionId)))
        .watchSingleOrNull();
  }

  /// Mode 1: opens a running Time session with the chosen block.
  Future<String> startTimeSession({
    required String tableId,
    required int minutes,
    required int price,
    required DateTime now,
  }) {
    return db.transaction(() {
      return _openSession(
        tableId: tableId,
        mode: PlayMode.time,
        now: now,
        endsAt: now.add(Duration(minutes: minutes)),
        baseMinutes: minutes,
        baseAmount: price,
        total: timeTotal(blockPrice: price),
      );
    });
  }

  /// Mode 2: opens an open-time Game session. The bill starts at 0 and builds up
  /// as [addGame] is called after each finished game.
  Future<String> startGameSession({required String tableId, required DateTime now}) {
    return db.transaction(() {
      return _openSession(tableId: tableId, mode: PlayMode.game, now: now);
    });
  }

  /// Race: the table fee is what the hall bills. [betTotal] is everything the
  /// players put down (bet money plus the table fee), kept for reference only.
  /// [minutes] is an optional time limit; without it the race has no countdown.
  Future<String> startRaceSession({
    required String tableId,
    required int raceTo,
    required int betTotal,
    required int tableFee,
    required DateTime now,
    int? minutes,
    String? note,
  }) {
    if (raceTo <= 0) throw ArgumentError('Race to must be at least 1');
    if (tableFee < 0 || betTotal < tableFee) {
      throw ArgumentError('Table fee must be between 0 and the race total');
    }
    if (minutes != null && minutes <= 0) throw ArgumentError('Minutes must be positive');

    return db.transaction(() async {
      final id = await _openSession(
        tableId: tableId,
        mode: PlayMode.race,
        now: now,
        endsAt: minutes == null ? null : now.add(Duration(minutes: minutes)),
        baseMinutes: minutes,
        total: raceTotal(tableFee: tableFee),
      );
      await db.into(db.raceDetails).insert(RaceDetailsCompanion.insert(
            sessionId: id,
            raceTo: raceTo,
            betTotal: betTotal,
            tableFee: tableFee,
            note: Value(note),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      return id;
    });
  }

  /// Mode 1: adds time to the end of a running session and the charge to the bill.
  Future<void> extend({
    required String sessionId,
    required int minutes,
    required int amount,
    required DateTime now,
  }) {
    return db.transaction(() async {
      final session = await _load(sessionId);
      if (session.status != SessionStatus.running || session.mode != PlayMode.time) {
        throw StateError('Only a running Time session can be extended');
      }

      await db.into(db.sessionExtensions).insert(SessionExtensionsCompanion.insert(
            sessionId: sessionId,
            minutes: minutes,
            amount: amount,
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await _update(
        sessionId,
        SessionsCompanion(endsAt: Value(session.endsAt!.add(Duration(minutes: minutes)))),
        now,
      );
      await recomputeSessionTotal(db, sessionId, now);
    });
  }

  /// Mode 2: one more finished game of [gameTypeId], at that game's current price.
  Future<void> addGame({
    required String sessionId,
    required String gameTypeId,
    required DateTime now,
  }) {
    return db.transaction(() async {
      final session = await _requireRunningGame(sessionId);
      final type =
          await (db.select(db.gameTypes)..where((g) => g.id.equals(gameTypeId))).getSingle();

      final same = await (db.select(db.sessionGames)
            ..where((g) =>
                g.sessionId.equals(sessionId) &
                g.gameTypeId.equals(gameTypeId) &
                g.unitPrice.equals(type.pricePerGame) &
                g.deletedAt.isNull()))
          .getSingleOrNull();

      if (same == null) {
        await db.into(db.sessionGames).insert(SessionGamesCompanion.insert(
              sessionId: sessionId,
              gameTypeId: gameTypeId,
              qty: 1,
              unitPrice: type.pricePerGame,
              amount: type.pricePerGame,
              createdAt: Value(now),
              updatedAt: Value(now),
            ));
      } else {
        await (db.update(db.sessionGames)..where((g) => g.id.equals(same.id))).write(
          SessionGamesCompanion(
            qty: Value(same.qty + 1),
            amount: Value((same.qty + 1) * same.unitPrice),
            updatedAt: Value(now),
            synced: const Value(false),
          ),
        );
      }
      await recomputeSessionTotal(db, session.id, now);
    });
  }

  /// Mode 2: takes back one game (a wrong tap). Logged in the audit log.
  Future<void> removeGame({
    required String sessionId,
    required String sessionGameId,
    String? reason,
    required DateTime now,
  }) {
    return db.transaction(() async {
      await _requireRunningGame(sessionId);
      final line = await (db.select(db.sessionGames)
            ..where((g) => g.id.equals(sessionGameId) & g.sessionId.equals(sessionId)))
          .getSingle();
      if (line.deletedAt != null || line.qty <= 0) return;

      final qty = line.qty - 1;
      await (db.update(db.sessionGames)..where((g) => g.id.equals(line.id))).write(
        SessionGamesCompanion(
          qty: Value(qty),
          amount: Value(qty * line.unitPrice),
          deletedAt: Value(qty == 0 ? now : null),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await db.into(db.auditLogs).insert(AuditLogsCompanion.insert(
            actor: DeviceContext.deviceId,
            action: 'game_removed',
            entity: 'session:$sessionId',
            oldValue: Value('qty ${line.qty}'),
            newValue: Value('qty $qty${reason == null ? '' : ': $reason'}'),
            at: now,
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await recomputeSessionTotal(db, sessionId, now);
    });
  }

  /// Stops the clock. The table now waits for payment with the final bill.
  Future<void> endTable({required String sessionId, required DateTime now}) {
    return db.transaction(() async {
      final session = await _load(sessionId);
      if (session.status != SessionStatus.running) {
        throw StateError('Only a running session can be ended');
      }
      await _update(
        sessionId,
        SessionsCompanion(
          status: const Value(SessionStatus.waitingToPay),
          endedAt: Value(now),
        ),
        now,
      );
    });
  }

  /// Records cash payment, then frees the table. Returns the change to give.
  Future<int> pay({
    required String sessionId,
    required int cashReceived,
    required DateTime now,
  }) {
    return db.transaction(() async {
      final session = await _load(sessionId);
      if (session.status != SessionStatus.waitingToPay) {
        throw StateError('End the table before taking payment');
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
      await _update(
        sessionId,
        const SessionsCompanion(status: Value(SessionStatus.paid)),
        now,
      );
      return change;
    });
  }

  /// Pay-and-close on a running table: stops the clock, takes the cash and frees
  /// the table in one step. A table already waiting to pay is just paid.
  Future<int> endAndPay({
    required String sessionId,
    required int cashReceived,
    required DateTime now,
  }) {
    return db.transaction(() async {
      final session = await _load(sessionId);
      if (session.status == SessionStatus.running) {
        await endTable(sessionId: sessionId, now: now);
      }
      return pay(sessionId: sessionId, cashReceived: cashReceived, now: now);
    });
  }

  /// Rejects a second open session on the same table, then inserts a running one.
  Future<String> _openSession({
    required String tableId,
    required PlayMode mode,
    required DateTime now,
    DateTime? endsAt,
    int? baseMinutes,
    int baseAmount = 0,
    int total = 0,
  }) async {
    final open = await (db.select(db.sessions)
          ..where((s) => s.tableId.equals(tableId) & s.status.isInValues(_openStatuses)))
        .get();
    if (open.isNotEmpty) throw StateError('This table already has an open session');

    final id = newId();
    await db.into(db.sessions).insert(SessionsCompanion.insert(
          id: Value(id),
          ref: Value(await nextRef(db, now)),
          openedBy: Value(DeviceContext.staffName),
          tableId: tableId,
          mode: mode,
          startedAt: now,
          endsAt: Value(endsAt),
          status: SessionStatus.running,
          baseMinutes: Value(baseMinutes),
          baseAmount: Value(baseAmount),
          total: Value(total),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
    return id;
  }

  Future<Session> _requireRunningGame(String sessionId) async {
    final session = await _load(sessionId);
    if (session.status != SessionStatus.running || session.mode != PlayMode.game) {
      throw StateError('Only a running Game session can change its games');
    }
    return session;
  }

  Future<Session> _load(String id) {
    return (db.select(db.sessions)..where((s) => s.id.equals(id))).getSingle();
  }

  Future<void> _update(String id, SessionsCompanion changes, DateTime now) {
    return (db.update(db.sessions)..where((s) => s.id.equals(id))).write(
      changes.copyWith(updatedAt: Value(now), synced: const Value(false)),
    );
  }
}
