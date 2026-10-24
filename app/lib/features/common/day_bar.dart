import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/day.dart';

/// Previous / next day arrows around the date. The next arrow stops at [today].
class DayBar extends StatelessWidget {
  const DayBar({super.key, required this.day, required this.today, required this.onChanged});

  final DateTime day;
  final DateTime today;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final isToday = isSameDay(day, today);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Previous day',
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(DateTime(day.year, day.month, day.day - 1)),
        ),
        Text(isToday ? 'Today' : DateFormat('EEE, MMM d').format(day),
            style: Theme.of(context).textTheme.titleMedium),
        IconButton(
          tooltip: 'Next day',
          icon: const Icon(Icons.chevron_right),
          onPressed: isToday ? null : () => onChanged(startOfNextDay(day)),
        ),
      ],
    );
  }
}
