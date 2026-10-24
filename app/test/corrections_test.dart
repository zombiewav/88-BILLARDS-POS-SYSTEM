import 'package:billiards_pos/data/complimentary_repository.dart';
import 'package:billiards_pos/data/database.dart';
import 'package:billiards_pos/data/expense_repository.dart';
import 'package:billiards_pos/data/history_repository.dart';
import 'package:billiards_pos/data/sale_repository.dart';
import 'package:billiards_pos/data/session_repository.dart';
import 'package:billiards_pos/data/void_repository.dart';
import 'package:billiards_pos/domain/enums.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessions;
  late SaleRepository sales;
  late ComplimentaryRepository free;
  late ExpenseRepository expenses;
  late VoidRepository voids;
  late HistoryRepository history;
  final t0 = DateTime(2026, 1, 1, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.init();
    sessions = SessionRepository(db);
    sales = SaleRepository(db);
    free = ComplimentaryRepository(db);
    expenses = ExpenseRepository(db);
    voids = VoidRepository(db);
    history = HistoryRepository(db);
  });

  tearDown(() => db.close());

  Future<Product> product(String name) =>
      (db.select(db.products)..where((p) => p.name.equals(name))).getSingle();

  Future<Session> sessionOf(String id) async => (await sessions.watchSession(id).first)!;

  Future<String> timeSession() async {
    final table = (await db.select(db.poolTables).get()).first;
    return sessions.startTimeSession(tableId: table.id, minutes: 30, price: 50, now: t0);
  }

  Future<String> raceSession() async {
    final table = (await db.select(db.poolTables).get()).first;
    return sessions.startRaceSession(
        tableId: table.id, raceTo: 5, betTotal: 1100, tableFee: 100, now: t0);
  }

  Future<String> paidTimeSession({int benta = 0}) async {
    final id = await timeSession();
    if (benta > 0) {
      await sales.addToTable(sessionId: id, cart: {(await product('Coke')).id: benta}, now: t0);
    }
    await sessions.endTable(sessionId: id, now: t0);
    final total = (await sessionOf(id)).total;
    await sessions.pay(sessionId: id, cashReceived: total, now: t0);
    return id;
  }

  group('complimentary drinks', () {
    test('cost the hall but not the customer, and take stock out', () async {
      final id = await raceSession();
      final coke = await product('Coke');

      await free.add(sessionId: id, productId: coke.id, qty: 2, now: t0);

      expect((await sessionOf(id)).total, 100);
      expect((await product('Coke')).stock, 22);

      final expense = (await db.select(db.expenses).get()).single;
      expect(expense.source, ExpenseSource.complimentary);
      expect(expense.amount, 20);

      final move = (await db.select(db.stockMovements).get())
          .firstWhere((m) => m.reason == StockReason.complimentary);
      expect(move.delta, -2);
    });

    test('use the selling price when no cost price is set', () async {
      final id = await raceSession();
      final coke = await product('Coke');
      await (db.update(db.products)..where((p) => p.id.equals(coke.id)))
          .write(const ProductsCompanion(costPrice: Value(null)));

      await free.add(sessionId: id, productId: coke.id, qty: 1, now: t0);
      expect((await db.select(db.expenses).get()).single.amount, 15);
    });

    test('are listed with names, and taking one back restores stock and expense', () async {
      final id = await raceSession();
      final coke = await product('Coke');
      final itemId = await free.add(sessionId: id, productId: coke.id, qty: 3, now: t0);

      final lines = await free.watch(id).first;
      expect(lines.single.name, 'Coke');
      expect(lines.single.qty, 3);

      await free.remove(itemId: itemId, now: t0);
      expect(await free.watch(id).first, isEmpty);
      expect((await product('Coke')).stock, 24);
      expect(
          (await db.select(db.expenses).get()).where((e) => e.deletedAt == null), isEmpty);
    });

    test('are only for open races', () async {
      final coke = await product('Coke');
      final time = await timeSession();
      await expectLater(
        free.add(sessionId: time, productId: coke.id, qty: 1, now: t0),
        throwsStateError,
      );

      final table = (await db.select(db.poolTables).get())[1];
      final race = await sessions.startRaceSession(
          tableId: table.id, raceTo: 3, betTotal: 100, tableFee: 50, now: t0);
      await sessions.endTable(sessionId: race, now: t0);
      await sessions.pay(sessionId: race, cashReceived: 50, now: t0);
      await expectLater(
        free.add(sessionId: race, productId: coke.id, qty: 1, now: t0),
        throwsStateError,
      );
    });

    test('too many for the stock changes nothing', () async {
      final id = await raceSession();
      final coke = await product('Coke');
      await expectLater(
        free.add(sessionId: id, productId: coke.id, qty: 99, now: t0),
        throwsStateError,
      );
      expect(await db.select(db.expenses).get(), isEmpty);
      expect(await free.watch(id).first, isEmpty);
    });
  });

  group('manual expenses', () {
    test('are added, listed for their day, and deleted with a reason', () async {
      final id = await expenses.add(name: 'Meryenda', amount: 100, now: t0);
      await expenses.add(name: 'Pentel', amount: 50, note: ' pens ', now: t0);
      await expenses.add(
          name: 'Yesterday', amount: 10, now: t0.subtract(const Duration(days: 1)));

      final today = await expenses.watchDay(t0).first;
      expect(today.map((e) => e.name).toSet(), {'Meryenda', 'Pentel'});
      expect(today.firstWhere((e) => e.name == 'Pentel').note, 'pens');

      await expenses.delete(id: id, reason: 'Entered twice', now: t0);
      expect((await expenses.watchDay(t0).first).map((e) => e.name), ['Pentel']);
      expect((await db.select(db.auditLogs).get()).single.action, 'expense_deleted');
    });

    test('reject blank names, zero amounts and a missing reason', () async {
      expect(() => expenses.add(name: ' ', amount: 10, now: t0), throwsArgumentError);
      expect(() => expenses.add(name: 'X', amount: 0, now: t0), throwsArgumentError);
      final id = await expenses.add(name: 'X', amount: 5, now: t0);
      expect(() => expenses.delete(id: id, reason: '  ', now: t0), throwsArgumentError);
    });

    test('complimentary expenses cannot be deleted from the list', () async {
      final race = await raceSession();
      await free.add(sessionId: race, productId: (await product('Coke')).id, qty: 1, now: t0);
      final expense = (await db.select(db.expenses).get()).single;
      await expectLater(
        expenses.delete(id: expense.id, reason: 'oops', now: t0),
        throwsStateError,
      );
    });
  });

  group('void', () {
    test('one benta item comes off an open bill and goes back to stock', () async {
      final id = await timeSession();
      final coke = await product('Coke');
      await sales.addToTable(sessionId: id, cart: {coke.id: 2}, now: t0);

      await voids.voidBentaUnit(
          sessionId: id, productId: coke.id, unitPrice: 15, reason: 'Wrong order', now: t0);

      expect((await sessionOf(id)).total, 50 + 15);
      expect((await product('Coke')).stock, 23);
      final lines = await sales.watchSessionBenta(id).first;
      expect(lines.single.qty, 1);

      final log = (await db.select(db.voidLogs).get()).single;
      expect(log.refType, voidRefSaleItem);
      expect(log.amount, 15);
      expect(log.reason, 'Wrong order');
    });

    test('removing the last unit empties the benta line', () async {
      final id = await timeSession();
      final coke = await product('Coke');
      await sales.addToTable(sessionId: id, cart: {coke.id: 1}, now: t0);
      await voids.voidBentaUnit(
          sessionId: id, productId: coke.id, unitPrice: 15, reason: 'x', now: t0);

      expect(await sales.watchSessionBenta(id).first, isEmpty);
      expect((await sessionOf(id)).total, 50);
      await expectLater(
        voids.voidBentaUnit(
            sessionId: id, productId: coke.id, unitPrice: 15, reason: 'x', now: t0),
        throwsStateError,
      );
    });

    test('a paid bill lists its table time and benta lines', () async {
      final id = await paidTimeSession(benta: 2);
      final lines = await voids.linesForSession(id);

      expect(lines.map((l) => l.label), ['Table time', 'Coke × 2']);
      expect(lines.map((l) => l.amount), [50, 30]);
      expect(lines.every((l) => !l.voided), isTrue);
    });

    test('voiding the table line refunds it without touching stock', () async {
      final id = await paidTimeSession(benta: 2);

      final refunded = await voids.voidLines(
        sessionId: id,
        keys: [VoidRepository.tableLineKey],
        reason: 'Wrong table',
        approvedBy: 'Owner',
        now: t0,
      );

      expect(refunded, 50);
      expect((await product('Coke')).stock, 22);
      final log = (await db.select(db.voidLogs).get()).single;
      expect(log.refType, voidRefPaidTable);
      expect(log.approvedBy, 'Owner');
      expect((await voids.linesForSession(id)).first.voided, isTrue);
      await expectLater(
        voids.voidLines(
            sessionId: id,
            keys: [VoidRepository.tableLineKey],
            reason: 'again',
            approvedBy: 'Owner',
            now: t0),
        throwsStateError,
      );
    });

    test('voiding a benta item refunds it and returns it to stock', () async {
      final id = await paidTimeSession(benta: 2);
      final item = (await voids.linesForSession(id)).firstWhere((l) => !l.isTable);

      final refunded = await voids.voidLines(
        sessionId: id,
        keys: [item.key],
        reason: 'Customer cancelled',
        approvedBy: 'Owner',
        now: t0,
      );

      expect(refunded, 30);
      expect((await product('Coke')).stock, 24);
      expect((await db.select(db.voidLogs).get()).single.refType, voidRefPaidItem);
    });

    test('a walk-in sale: partial void keeps it, voiding every item voids the sale', () async {
      final coke = await product('Coke');
      final royal = await product('Royal');
      await sales.sellStandalone(
          cart: {coke.id: 1, royal.id: 1}, cashReceived: 30, now: t0);
      final sale = (await db.select(db.sales).get()).single;
      final lines = await voids.linesForSale(sale.id);
      expect(lines.length, 2);

      await voids.voidLines(
          saleId: sale.id,
          keys: [lines.first.key],
          reason: 'Wrong item',
          approvedBy: 'Owner',
          now: t0);
      expect((await db.select(db.sales).get()).single.status, saleCompleted);

      await voids.voidLines(
          saleId: sale.id,
          keys: [lines.last.key],
          reason: 'Wrong item',
          approvedBy: 'Owner',
          now: t0);
      expect((await db.select(db.sales).get()).single.status, saleVoided);
      expect((await product('Coke')).stock, 24);
      expect((await product('Royal')).stock, 24);
    });

    test('a sale on a table bill cannot be voided as a walk-in sale', () async {
      final id = await timeSession();
      await sales.addToTable(sessionId: id, cart: {(await product('Coke')).id: 1}, now: t0);
      final sale = (await db.select(db.sales).get()).single;
      await expectLater(
        voids.voidLines(
            saleId: sale.id, keys: ['x'], reason: 'x', approvedBy: 'Owner', now: t0),
        throwsStateError,
      );
    });

    test('only a paid bill can be voided, with a reason and at least one line', () async {
      final paid = await paidTimeSession();
      final open = await timeSession();
      await expectLater(
        voids.voidLines(
            sessionId: open,
            keys: [VoidRepository.tableLineKey],
            reason: 'x',
            approvedBy: 'Owner',
            now: t0),
        throwsStateError,
      );

      expect(
        () => voids.voidLines(
            sessionId: paid,
            keys: [VoidRepository.tableLineKey],
            reason: '  ',
            approvedBy: 'Owner',
            now: t0),
        throwsArgumentError,
      );
      expect(
        () => voids.voidLines(
            sessionId: paid, keys: [], reason: 'x', approvedBy: 'Owner', now: t0),
        throwsArgumentError,
      );
    });

    test('voids are written to the audit log with who approved them', () async {
      final id = await paidTimeSession();
      await voids.voidLines(
          sessionId: id,
          keys: [VoidRepository.tableLineKey],
          reason: 'Refund',
          approvedBy: 'Boss',
          now: t0);
      final audit = await db.select(db.auditLogs).get();
      final entry = audit.firstWhere((a) => a.action == 'void_$voidRefPaidTable');
      expect(entry.newValue, contains('approved by Boss'));
      expect(entry.actor, DeviceContext.deviceId);
    });
  });

  group('unpaid bills', () {
    Future<String> endedTimeSession() async {
      final id = await timeSession();
      await sessions.endTable(sessionId: id, now: t0);
      return id;
    }

    test('marking unpaid frees the table and lists the bill', () async {
      final id = await endedTimeSession();
      await voids.markUnpaid(sessionId: id, reason: 'Left without paying', now: t0);

      expect((await sessionOf(id)).status, SessionStatus.unpaid);
      expect((await sessionOf(id)).note, 'Left without paying');
      expect((await sessions.watchTables().first).every((r) => r.session == null), isTrue);

      final unpaid = await history.watchUnpaid().first;
      expect(unpaid.single.session.id, id);
      expect(unpaid.single.tableLabel, 'T1');
    });

    test('the table can be started again, and a running table cannot be marked unpaid', () async {
      final id = await endedTimeSession();
      await voids.markUnpaid(sessionId: id, reason: 'Left', now: t0);
      final table = (await db.select(db.poolTables).get()).first;
      final running = await sessions.startTimeSession(
          tableId: table.id, minutes: 30, price: 50, now: t0);

      await expectLater(
        voids.markUnpaid(sessionId: running, reason: 'x', now: t0),
        throwsStateError,
      );
    });

    test('settling takes the cash later and removes it from the list', () async {
      final id = await endedTimeSession();
      await voids.markUnpaid(sessionId: id, reason: 'Left', now: t0);

      final later = t0.add(const Duration(days: 1));
      expect(await voids.settleUnpaid(sessionId: id, cashReceived: 100, now: later), 50);

      expect((await sessionOf(id)).status, SessionStatus.paid);
      expect(await history.watchUnpaid().first, isEmpty);
      final paidToday = await history.watchPaidSessions(later).first;
      expect(paidToday.single.session.id, id);
      expect(await history.watchPaidSessions(t0).first, isEmpty);
    });

    test('writing off keeps the record and removes it from the list', () async {
      final id = await endedTimeSession();
      await voids.markUnpaid(sessionId: id, reason: 'Left', now: t0);
      await voids.writeOffUnpaid(sessionId: id, reason: 'Never came back', now: t0);

      expect(await history.watchUnpaid().first, isEmpty);
      expect((await db.select(db.voidLogs).get()).single.refType, voidRefUnpaid);
      await expectLater(
        voids.settleUnpaid(sessionId: id, cashReceived: 100, now: t0),
        throwsStateError,
      );
    });
  });

  group('history', () {
    test('lists paid bills and walk-in sales for the day only', () async {
      final billId = await paidTimeSession();
      final coke = await product('Coke');
      await sales.sellStandalone(cart: {coke.id: 1}, cashReceived: 15, now: t0);

      final paid = await history.watchPaidSessions(t0).first;
      expect(paid.single.session.id, billId);
      expect(paid.single.payment.amount, 50);

      final walkIns = await history.watchWalkInSales(t0).first;
      expect(walkIns.single.sale.total, 15);

      expect(await history.watchPaidSessions(t0.add(const Duration(days: 1))).first, isEmpty);
    });
  });
}
