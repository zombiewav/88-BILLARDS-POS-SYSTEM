import 'enums.dart';

/// Time left on a Time-mode session, never negative.
Duration remainingTime(DateTime endsAt, DateTime now) {
  final left = endsAt.difference(now);
  return left.isNegative ? Duration.zero : left;
}

/// Status shown on the Tables dashboard. Paid and unpaid sessions free the table.
/// Any running session with an end time (Time, or a Race with a set time) can go
/// "Ending soon"; open-ended sessions (Game) never do.
TableStatus tableStatusFor({
  required SessionStatus? sessionStatus,
  required DateTime? endsAt,
  required DateTime now,
  required int alertMinutes,
}) {
  switch (sessionStatus) {
    case null:
    case SessionStatus.paid:
    case SessionStatus.unpaid:
      return TableStatus.free;
    case SessionStatus.waitingToPay:
      return TableStatus.waitingToPay;
    case SessionStatus.running:
      if (endsAt != null) {
        final left = remainingTime(endsAt, now);
        if (left <= Duration(minutes: alertMinutes)) return TableStatus.endingSoon;
      }
      return TableStatus.playing;
  }
}
