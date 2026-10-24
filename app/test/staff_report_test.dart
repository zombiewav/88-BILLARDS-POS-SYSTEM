import 'package:billiards_pos/data/complimentary_repository.dart';
import 'package:billiards_pos/data/database.dart';
import 'package:billiards_pos/data/expense_repository.dart';
import 'package:billiards_pos/data/report_repository.dart';
import 'package:billiards_pos/data/sale_repository.dart';
import 'package:billiards_pos/data/session_repository.dart';
import 'package:billiards_pos/data/staff_repository.dart';
import 'package:billiards_pos/data/void_repository.dart';
import 'package:billiards_pos/domain/enums.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  final t0 = DateTime(2026, 10, 21, 12);

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.init();
    DeviceContext.staffName = null;
  });

  tearDown(() => db.close());

  group('staff and PINs', () {
    late StaffRepository staff;
    setUp(() => staff = StaffRepository(db));

    test('PINs are 6 digits, unique, and stored hashed', () async {
      expect(() => staff.create(name: 'A', role: StaffRole.owner, pin: '12345', now: t0),
          throwsArgumentError);
      expect(() => staff.create(name: 'A', role: StaffRole.owner, pin: 'abcdef', now: t0),
          throwsArgumentError);

      final owner = await staff.create(name: 'Boss', role: StaffRole.owner, pin: '123456', now: t0);
      expect(owner.pinHash, isNot(contains('123456')));
      expect(owner.pinHash.length, 64);
      await expectLater(
        staff.create(name: 'Dup', role: StaffRole.cashier, pin: '123456', now: t0),
        throwsStateError,
      );
    });

    test('hasOwner is false until an owner is created', () async {
      expect(await staff.hasOwner(), isFalse);
      await staff.create(name: 'Cash', role: StaffRole.cashier, pin: '111111', now: t0);
      expect(await staff.hasOwner(), isFalse);
      await staff.create(name: 'Boss', role: StaffRole.owner, pin: '222222', now: t0);
      expect(await staff.hasOwner(), isTrue);
    });

    test('the PIN decides who logs in and their role', () async {
      await staff.create(name: 'Boss', role: StaffRole.owner, pin: '222222', now: t0);
      await staff.create(name: 'Cash', role: StaffRole.cashier, pin: '111111', now: t0);

      final result = await staff.login('111111', now: t0);
      expect(result, isA<PinOk>());
      expect((result as PinOk).staff.name, 'Cash');
      expect(result.staff.role, StaffRole.cashier);
    });

    test('wrong tries count down, then the keypad locks for 5 minutes', () async {
      await staff.create(name: 'Boss', role: StaffRole.owner, pin: '222222', now: t0);

      for (var left = 4; left >= 1; left--) {
        final r = await staff.login('000000', now: t0);
        expect((r as PinWrong).triesLeft, left);
      }
      final locked = await staff.login('000000', now: t0);
      expect(locked, isA<PinLocked>());
      expect((locked as PinLocked).until, t0.add(const Duration(minutes: 5)));

      // Even the right PIN is refused while locked.
      expect(await staff.login('222222', now: t0.add(const Duration(minutes: 1))),
          isA<PinLocked>());
      // After 5 minutes it works again and the counter starts over.
      expect(await staff.login('222222', now: t0.add(const Duration(minutes: 6))), isA<PinOk>());
      expect(((await staff.login('000000', now: t0.add(const Duration(minutes: 7)))) as PinWrong)
          .triesLeft, 4);
    });

    test('a correct PIN resets the wrong-try counter', () async {
      await staff.create(name: 'Boss', role: StaffRole.owner, pin: '222222', now: t0);
      await staff.login('000000', now: t0);
      await staff.login('000000', now: t0);
      await staff.login('222222', now: t0);
      expect(((await staff.login('000000', now: t0)) as PinWrong).triesLeft, 4);
    });

    test('failed PIN attempts are in the audit log', () async {
      await staff.create(name: 'Boss', role: StaffRole.owner, pin: '222222', now: t0);
      await staff.login('000000', now: t0);
      expect((await db.select(db.auditLogs).get()).map((a) => a.action), contains('pin_failed'));
    });

    test('owner approval accepts only an owner PIN', () async {
      await staff.create(name: 'Boss', role: StaffRole.owner, pin: '222222', now: t0);
      await staff.create(name: 'Cash', role: StaffRole.cashier, pin: '111111', now: t0);

      expect(await staff.approveAsOwner('111111', now: t0), isA<PinWrong>());
      final ok = await staff.approveAsOwner('222222', now: t0);
      expect((ok as PinOk).staff.name, 'Boss');
    });

    test('resetting a PIN replaces the old one; the last owner cannot be removed', () async {
      final boss = await staff.create(name: 'Boss', role: StaffRole.owner, pin: '222222', now: t0);
      final cash = await staff.create(name: 'Cash', role: StaffRole.cashier, pin: '111111', now: t0);

      await staff.resetPin(staffId: cash.id, newPin: '333333', now: t0);
      expect(await staff.login('111111', now: t0), isA<PinWrong>());
      expect(await staff.login('333333', now: t0), isA<PinOk>());
      await expectLater(
        staff.resetPin(staffId: cash.id, newPin: '222222', now: t0),
        throwsStateError,
      );

      await expectLater(staff.remove(staffId: boss.id, now: t0), throwsStateError);
      await staff.remove(staffId: cash.id, now: t0);
      expect(await staff.login('333333', now: t0), isA<PinWrong>());
    });
  });

  group('references', () {
    test('sessions and sales share the day count and restart each day', () async {
      final sessions = SessionRepository(db);
      final sales = SaleRepository(db);
      final tables = await db.select(db.poolTables).get();
      final coke = await (db.select(db.products)..where((p) => p.name.equals('Coke'))).getSingle();
      DeviceContext.staffName = 'Cash';

      final first = await sessions.startTimeSession(
          tableId: tables[0].id, minutes: 30, price: 50, now: t0);
      await sales.sellStandalone(cart: {coke.id: 1}, cashReceived: 15, now: t0);
      final third = await sessions.startTimeSession(
          tableId: tables[1].id, minutes: 30, price: 50, now: t0);
      final tomorrow = await sessions.startTimeSession(
          tableId: tables[2].id, minutes: 30, price: 50, now: t0.add(const Duration(days: 1)));

      Future<Session> s(String id) async => (await sessions.watchSession(id).first)!;
      expect((await s(first)).ref, '1021-01');
      expect((await db.select(db.sales).get()).single.ref, '1021-02');
      expect((await s(third)).ref, '1021-03');
      expect((await s(tomorrow)).ref, '1022-01');
      expect((await s(first)).openedBy, 'Cash');
    });
  });

  group('report', () {
    late SessionRepository sessions;
    late SaleRepository sales;
    late ExpenseRepository expenses;
    late VoidRepository voids;
    late ReportRepository report;

    setUp(() {
      sessions = SessionRepository(db);
      sales = SaleRepository(db);
      expenses = ExpenseRepository(db);
      voids = VoidRepository(db);
      report = ReportRepository(db);
    });

    Future<String> table() async => (await db.select(db.poolTables).get()).first.id;

    Future<String> paidTime(int price, {DateTime? at}) async {
      final now = at ?? t0;
      final id = await sessions.startTimeSession(
          tableId: await table(), minutes: 30, price: price, now: now);
      await sessions.endTable(sessionId: id, now: now);
      await sessions.pay(sessionId: id, cashReceived: price, now: now);
      return id;
    }

    Future<void> paidRace(int fee, {DateTime? at}) async {
      final now = at ?? t0;
      final id = await sessions.startRaceSession(
          tableId: await table(), raceTo: 5, betTotal: fee + 600, tableFee: fee, now: now);
      await sessions.endTable(sessionId: id, now: now);
      await sessions.pay(sessionId: id, cashReceived: fee, now: now);
    }

    Future<Product> product(String name) =>
        (db.select(db.products)..where((p) => p.name.equals(name))).getSingle();

    test('the notebook day nets 1,335', () async {
      for (final p in [50, 15, 50]) {
        await paidTime(p);
      }
      for (final fee in [400, 250, 400, 200]) {
        await paidRace(fee);
      }
      final royal = await product('Royal');
      final coke = await product('Coke');
      await sales.sellStandalone(cart: {royal.id: 3}, cashReceived: 45, now: t0);
      await sales.sellStandalone(cart: {royal.id: 3}, cashReceived: 45, now: t0);
      await sales.sellStandalone(cart: {coke.id: 2}, cashReceived: 30, now: t0);
      await expenses.add(name: 'Meryenda', amount: 100, now: t0);
      await expenses.add(name: 'Pentel', amount: 50, now: t0);

      final day = await report.day(t0);
      expect(day.timeParts, [50, 15, 50]);
      expect(day.raceParts, [400, 250, 400, 200]);
      expect(day.bentaTotal, 120);
      expect(day.bentaParts.firstWhere((b) => b.name == 'Royal').qty, 6);
      final t = day.totals;
      expect(t.timeIncome, 115);
      expect(t.raceIncome, 1250);
      expect(t.billiard, 1365);
      expect(t.billiardPlusBenta, 1485);
      expect(t.expenses, 150);
      expect(t.net, 1335);
    });

    test('benta on a paid table bill counts as benta, not table income', () async {
      final id = await sessions.startTimeSession(
          tableId: await table(), minutes: 30, price: 50, now: t0);
      await sales.addToTable(sessionId: id, cart: {(await product('Coke')).id: 2}, now: t0);
      await sessions.endTable(sessionId: id, now: t0);
      await sessions.pay(sessionId: id, cashReceived: 80, now: t0);

      final t = (await report.day(t0)).totals;
      expect(t.timeIncome, 50);
      expect(t.benta, 30);
      expect(t.net, 80);
    });

    test('refunds are subtracted; item voids on open bills and write-offs are not', () async {
      final id = await paidTime(50);
      await voids.voidLines(
          sessionId: id,
          keys: [VoidRepository.tableLineKey],
          reason: 'Refund',
          approvedBy: 'Boss',
          now: t0);

      // An item removed from an open bill, and an unpaid bill written off.
      final open = await sessions.startTimeSession(
          tableId: await table(), minutes: 30, price: 50, now: t0);
      final coke = await product('Coke');
      await sales.addToTable(sessionId: open, cart: {coke.id: 1}, now: t0);
      await voids.voidBentaUnit(
          sessionId: open, productId: coke.id, unitPrice: 15, reason: 'Wrong', now: t0);
      await sessions.endTable(sessionId: open, now: t0);
      await voids.markUnpaid(sessionId: open, reason: 'Left', now: t0);
      await voids.writeOffUnpaid(sessionId: open, reason: 'Gone', now: t0);

      final day = await report.day(t0);
      expect(day.totals.timeIncome, 50);
      expect(day.voids, 50);
      expect(day.writtenOff, 65);
      expect(day.totals.net, 0);
    });

    test('free drinks and manual expenses both reduce the net', () async {
      final race = await sessions.startRaceSession(
          tableId: await table(), raceTo: 5, betTotal: 700, tableFee: 100, now: t0);
      await ComplimentaryRepository(db)
          .add(sessionId: race, productId: (await product('Coke')).id, qty: 2, now: t0);
      await sessions.endTable(sessionId: race, now: t0);
      await sessions.pay(sessionId: race, cashReceived: 100, now: t0);
      await expenses.add(name: 'Ice', amount: 40, category: 'Supplies', now: t0);

      final day = await report.day(t0);
      expect(day.totals.expenses, 60);
      expect(day.totals.net, 100 - 60);
    });

    test('unpaid bills are income only on the day they are settled', () async {
      final id = await sessions.startTimeSession(
          tableId: await table(), minutes: 30, price: 50, now: t0);
      await sessions.endTable(sessionId: id, now: t0);
      await voids.markUnpaid(sessionId: id, reason: 'Left', now: t0);
      expect((await report.day(t0)).totals.net, 0);

      final later = t0.add(const Duration(days: 1));
      await voids.settleUnpaid(sessionId: id, cashReceived: 50, now: later);
      expect((await report.day(t0)).totals.net, 0);
      expect((await report.day(later)).totals.net, 50);
    });

    test('week, month and the 7-day series add up across days', () async {
      await paidTime(100, at: t0); // Wed Oct 21
      await paidTime(50, at: t0.subtract(const Duration(days: 2))); // Mon Oct 19
      await paidTime(30, at: t0.subtract(const Duration(days: 10))); // Oct 11, a week earlier

      expect((await report.day(t0)).totals.net, 100);
      expect((await report.week(t0)).totals.net, 150);
      expect((await report.month(t0)).totals.net, 180);
      expect(await report.netSeries(t0), [0, 0, 0, 0, 50, 0, 100]);
    });
  });
}
