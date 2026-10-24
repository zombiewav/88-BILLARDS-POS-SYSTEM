import 'package:drift/drift.dart';

import '../core/day.dart';
import '../domain/billing.dart';
import '../domain/enums.dart';
import 'database.dart';

enum ReportPeriod { daily, weekly, monthly }

typedef BentaPart = ({String name, int qty});
typedef ExpensePart = ({String name, int amount});

/// Everything the Report screen shows for one stretch of days.
///
/// Income counts when a bill is paid. Voids (refunds of paid lines) are
/// subtracted on the day they were made. Write-offs and open-bill item voids
/// never reached income, so they are only reported, not subtracted.
class PeriodReport {
  const PeriodReport({
    required this.from,
    required this.to,
    required this.timeParts,
    required this.gameParts,
    required this.raceParts,
    required this.bentaParts,
    required this.bentaTotal,
    required this.expenseParts,
    required this.voids,
    required this.writtenOff,
  });

  final DateTime from;
  final DateTime to;

  /// One amount per paid session, by mode (the table income, benta excluded).
  final List<int> timeParts;
  final List<int> gameParts;
  final List<int> raceParts;

  /// Benta income: walk-in sales and benta on paid table bills.
  final List<BentaPart> bentaParts;
  final int bentaTotal;
  final List<ExpensePart> expenseParts;
  final int voids;
  final int writtenOff;

  static int _sum(Iterable<int> xs) => xs.fold(0, (a, b) => a + b);

  DailyTotals get totals => DailyTotals(
        timeIncome: _sum(timeParts),
        gameIncome: _sum(gameParts),
        raceIncome: _sum(raceParts),
        benta: bentaTotal,
        expenses: _sum(expenseParts.map((e) => e.amount)),
        voids: voids,
      );
}

/// Builds [PeriodReport]s from paid bills, sales, expenses and voids.
class ReportRepository {
  ReportRepository(this.db);

  final AppDatabase db;

  Future<PeriodReport> day(DateTime day) => period(startOfDay(day), startOfNextDay(day));

  Future<PeriodReport> week(DateTime day) {
    final from = startOfWeek(day);
    return period(from, DateTime(from.year, from.month, from.day + 7));
  }

  Future<PeriodReport> month(DateTime day) =>
      period(startOfMonth(day), startOfNextMonth(day));

  /// The report for the day, week or month that contains [anchor].
  Future<PeriodReport> forPeriod(ReportPeriod period, DateTime anchor) => switch (period) {
        ReportPeriod.daily => day(anchor),
        ReportPeriod.weekly => week(anchor),
        ReportPeriod.monthly => month(anchor),
      };

  /// Net profit for each of the [days] days ending on [lastDay], oldest first.
  Future<List<int>> netSeries(DateTime lastDay, {int days = 7}) async {
    final end = startOfDay(lastDay);
    final nets = <int>[];
    for (var i = days - 1; i >= 0; i--) {
      final d = DateTime(end.year, end.month, end.day - i);
      nets.add((await day(d)).totals.net);
    }
    return nets;
  }

  Future<PeriodReport> period(DateTime from, DateTime to) async {
    // Paid table bills: what was paid, minus the benta that was on the bill.
    final bills = await (db.select(db.payments).join([
      innerJoin(db.sessions, db.sessions.id.equalsExp(db.payments.sessionId)),
    ])
          ..where(_paidIn(from, to)))
        .get();

    final sessionIds = [for (final b in bills) b.readTable(db.sessions).id];
    final bentaBySession = <String, int>{};
    if (sessionIds.isNotEmpty) {
      final sales = await (db.select(db.sales)
            ..where((s) =>
                s.sessionId.isIn(sessionIds) &
                s.status.equals(saleCompleted) &
                s.deletedAt.isNull()))
          .get();
      for (final s in sales) {
        bentaBySession[s.sessionId!] = (bentaBySession[s.sessionId!] ?? 0) + s.total;
      }
    }

    final timeParts = <int>[];
    final gameParts = <int>[];
    final raceParts = <int>[];
    var benta = 0;
    for (final b in bills) {
      final session = b.readTable(db.sessions);
      final paid = b.readTable(db.payments).amount;
      final bentaPart = bentaBySession[session.id] ?? 0;
      benta += bentaPart;
      final table = paid - bentaPart;
      switch (session.mode) {
        case PlayMode.time:
          timeParts.add(table);
        case PlayMode.game:
          gameParts.add(table);
        case PlayMode.race:
          raceParts.add(table);
      }
    }

    // Walk-in sales are all benta.
    final walkIns = await (db.select(db.payments).join([
      innerJoin(db.sales, db.sales.id.equalsExp(db.payments.saleId)),
    ])
          ..where(_paidIn(from, to)))
        .get();
    final walkInSaleIds = [for (final w in walkIns) w.readTable(db.sales).id];
    for (final w in walkIns) {
      benta += w.readTable(db.payments).amount;
    }

    // Which products made up that benta.
    final bentaQty = <String, int>{};
    Future<void> addItems(Expression<bool> saleFilter) async {
      final rows = await (db.select(db.saleItems).join([
        innerJoin(db.sales, db.sales.id.equalsExp(db.saleItems.saleId)),
        innerJoin(db.products, db.products.id.equalsExp(db.saleItems.productId)),
      ])
            ..where(saleFilter &
                db.saleItems.deletedAt.isNull() &
                db.saleItems.qty.isBiggerThanValue(0)))
          .get();
      for (final r in rows) {
        final name = r.readTable(db.products).name;
        bentaQty[name] = (bentaQty[name] ?? 0) + r.readTable(db.saleItems).qty;
      }
    }

    if (sessionIds.isNotEmpty) {
      await addItems(db.sales.sessionId.isIn(sessionIds) & db.sales.status.equals(saleCompleted));
    }
    if (walkInSaleIds.isNotEmpty) await addItems(db.sales.id.isIn(walkInSaleIds));

    final expenseRows = await (db.select(db.expenses)
          ..where((e) =>
              e.date.isBiggerOrEqualValue(from) &
              e.date.isSmallerThanValue(to) &
              e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.asc(e.date)]))
        .get();

    final voidRows = await (db.select(db.voidLogs)
          ..where((v) =>
              v.at.isBiggerOrEqualValue(from) &
              v.at.isSmallerThanValue(to) &
              v.deletedAt.isNull()))
        .get();
    var voids = 0;
    var writtenOff = 0;
    for (final v in voidRows) {
      if (incomeVoidKinds.contains(v.refType)) {
        voids += v.amount;
      } else {
        writtenOff += v.amount;
      }
    }

    return PeriodReport(
      from: from,
      to: to,
      timeParts: timeParts,
      gameParts: gameParts,
      raceParts: raceParts,
      bentaParts: [for (final e in bentaQty.entries) (name: e.key, qty: e.value)],
      bentaTotal: benta,
      expenseParts: [for (final e in expenseRows) (name: e.name, amount: e.amount)],
      voids: voids,
      writtenOff: writtenOff,
    );
  }

  Expression<bool> _paidIn(DateTime from, DateTime to) {
    return db.payments.paidAt.isBiggerOrEqualValue(from) &
        db.payments.paidAt.isSmallerThanValue(to) &
        db.payments.deletedAt.isNull();
  }
}
