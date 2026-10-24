/// Midnight at the start of [t]'s calendar day (local time).
DateTime startOfDay(DateTime t) => DateTime(t.year, t.month, t.day);

/// Midnight at the start of the following day.
DateTime startOfNextDay(DateTime t) => DateTime(t.year, t.month, t.day + 1);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Monday of [t]'s week.
DateTime startOfWeek(DateTime t) => DateTime(t.year, t.month, t.day - (t.weekday - 1));

DateTime startOfMonth(DateTime t) => DateTime(t.year, t.month);

DateTime startOfNextMonth(DateTime t) => DateTime(t.year, t.month + 1);
