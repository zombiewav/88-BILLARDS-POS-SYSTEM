import 'package:drift/drift.dart';

import 'database.dart';

/// The next short reference for a session or sale, like `0421-04`:
/// month and day, then the number of the day (sessions and sales share the count).
Future<String> nextRef(AppDatabase db, DateTime now) async {
  final prefix = '${_two(now.month)}${_two(now.day)}-';

  Future<int> countIn(TableInfo table, GeneratedColumn<String> ref) async {
    final count = ref.count();
    final row = await (db.selectOnly(table)
          ..addColumns([count])
          ..where(ref.like('$prefix%')))
        .getSingle();
    return row.read(count) ?? 0;
  }

  final used = await countIn(db.sessions, db.sessions.ref) + await countIn(db.sales, db.sales.ref);
  return '$prefix${_two(used + 1)}';
}

String _two(int n) => n.toString().padLeft(2, '0');
