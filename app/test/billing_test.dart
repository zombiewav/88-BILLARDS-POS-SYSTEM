import 'package:billiards_pos/domain/billing.dart';
import 'package:billiards_pos/domain/enums.dart';
import 'package:billiards_pos/domain/table_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bill math', () {
    test('time total is block price plus extensions', () {
      expect(timeTotal(blockPrice: 50), 50);
      expect(timeTotal(blockPrice: 50, extensionAmounts: [50, 100]), 200);
    });

    test('game total is games times price per game', () {
      expect(gameTotal(const [GameLine(2, 15), GameLine(1, 20)]), 50);
      expect(gameTotal(const []), 0);
    });

    test('race income is the table fee only', () {
      expect(raceTotal(tableFee: 100), 100);
    });

    test('table bill adds benta', () {
      expect(tableBill(modeTotal: 100, bentaTotal: 45), 145);
    });

    test('change is cash minus total, and short cash throws', () {
      expect(changeDue(total: 150, cashReceived: 200), 50);
      expect(changeDue(total: 150, cashReceived: 150), 0);
      expect(() => changeDue(total: 150, cashReceived: 100), throwsArgumentError);
    });

    test('notebook day 10-20 nets 1,335', () {
      const day = DailyTotals(
        timeIncome: 50 + 15 + 50,
        raceIncome: 400 + 250 + 400 + 200,
        benta: 3 * 15 + 3 * 15 + 2 * 15,
        expenses: 100 + 50,
      );
      expect(day.billiard, 1365);
      expect(day.billiardPlusBenta, 1485);
      expect(day.net, 1335);
    });
  });

  group('table status', () {
    final now = DateTime(2026, 1, 1, 12);

    TableStatus statusOf(SessionStatus? s, {DateTime? endsAt}) => tableStatusFor(
          sessionStatus: s,
          endsAt: endsAt,
          now: now,
          alertMinutes: 5,
        );

    test('no session, paid and unpaid are free', () {
      expect(statusOf(null), TableStatus.free);
      expect(statusOf(SessionStatus.paid), TableStatus.free);
      expect(statusOf(SessionStatus.unpaid), TableStatus.free);
    });

    test('running with plenty of time is playing', () {
      expect(statusOf(SessionStatus.running, endsAt: now.add(const Duration(minutes: 20))),
          TableStatus.playing);
    });

    test('running inside the alert window is ending soon, including time up', () {
      expect(statusOf(SessionStatus.running, endsAt: now.add(const Duration(minutes: 5))),
          TableStatus.endingSoon);
      expect(statusOf(SessionStatus.running, endsAt: now.subtract(const Duration(minutes: 3))),
          TableStatus.endingSoon);
    });

    test('open-ended sessions (no end time) never go ending soon', () {
      expect(statusOf(SessionStatus.running), TableStatus.playing);
    });

    test('ended session waits to pay', () {
      expect(statusOf(SessionStatus.waitingToPay), TableStatus.waitingToPay);
    });

    test('remaining time never goes negative', () {
      expect(remainingTime(now.subtract(const Duration(minutes: 1)), now), Duration.zero);
    });
  });
}
