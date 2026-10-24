import 'package:intl/intl.dart';

final _number = NumberFormat.decimalPattern();

String formatPeso(int amount) => '₱${_number.format(amount)}';

String formatClock(DateTime time) => DateFormat('h:mm a').format(time);

String _two(int n) => n.toString().padLeft(2, '0');

/// 1:05:09 for an hour or more, otherwise 05:09.
String formatCountdown(Duration d) {
  final total = d.isNegative ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// "Synced 2 min ago" / "Not synced yet".
String syncLabel(DateTime? lastSync, DateTime now) {
  if (lastSync == null) return 'Not synced yet';
  final mins = now.difference(lastSync).inMinutes;
  return mins < 1 ? 'Synced just now' : 'Synced $mins min ago';
}

/// Short label for a time-rate tile: ½ hr, 1 hr, 1½ hr, 2 hr (otherwise like [formatMinutes]).
String formatRateLabel(int minutes) {
  if (minutes % 30 != 0 || minutes <= 0) return formatMinutes(minutes);
  final halves = minutes ~/ 30;
  final hours = halves ~/ 2;
  final half = halves.isOdd;
  if (hours == 0) return '½ hr';
  return half ? '$hours½ hr' : '$hours hr';
}

/// 30 min, 1 hr, 1 hr 30 min.
String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h hr' : '$h hr $m min';
}
