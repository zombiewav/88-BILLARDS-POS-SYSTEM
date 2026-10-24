import 'package:drift/drift.dart';

import '../core/day.dart';
import '../domain/enums.dart';
import 'audit.dart';
import 'database.dart';

/// Manual expenses (meryenda, pentel). Complimentary drinks add their own
/// expense rows through [ComplimentaryRepository].
class ExpenseRepository {
  ExpenseRepository(this.db);

  final AppDatabase db;

  /// Expenses dated on [day], newest first.
  Stream<List<Expense>> watchDay(DateTime day) => watchRange(startOfDay(day), startOfNextDay(day));

  /// Expenses from [from] up to (not including) [to], newest first.
  Stream<List<Expense>> watchRange(DateTime from, DateTime to) {
    return (db.select(db.expenses)
          ..where((e) =>
              e.date.isBiggerOrEqualValue(from) &
              e.date.isSmallerThanValue(to) &
              e.deletedAt.isNull())
          ..orderBy([(e) => OrderingTerm.desc(e.date)]))
        .watch();
  }

  Future<String> add({
    required String name,
    required int amount,
    String category = 'Other',
    String? note,
    required DateTime now,
  }) async {
    if (name.trim().isEmpty) throw ArgumentError('Name is required');
    if (amount <= 0) throw ArgumentError('Amount must be more than 0');

    final id = newId();
    final cleanNote = note?.trim();
    await db.into(db.expenses).insert(ExpensesCompanion.insert(
          id: Value(id),
          name: name.trim(),
          amount: amount,
          category: Value(category),
          date: now,
          source: ExpenseSource.manual,
          note: Value(cleanNote == null || cleanNote.isEmpty ? null : cleanNote),
          createdAt: Value(now),
          updatedAt: Value(now),
        ));
    return id;
  }

  /// Removes a manual expense (kept in the database and audit log, hidden from lists).
  Future<void> delete({required String id, required String reason, required DateTime now}) {
    final why = requireReason(reason);
    return db.transaction(() async {
      final expense =
          await (db.select(db.expenses)..where((e) => e.id.equals(id))).getSingle();
      if (expense.source != ExpenseSource.manual) {
        throw StateError('Free drinks are removed from the race, not from Expenses');
      }
      if (expense.deletedAt != null) return;

      await (db.update(db.expenses)..where((e) => e.id.equals(id))).write(ExpensesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await writeAudit(db,
          action: 'expense_deleted',
          entity: 'expense:$id',
          oldValue: '${expense.name} ${expense.amount}',
          newValue: why,
          now: now);
    });
  }
}
