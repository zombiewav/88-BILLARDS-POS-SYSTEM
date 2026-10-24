import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../core/day.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../providers.dart';
import '../common/reason_dialog.dart';

enum _Range { today, week, month }

const _categories = ['Food', 'Supplies', 'Utilities', 'Other'];

class ExpensesPage extends ConsumerStatefulWidget {
  const ExpensesPage({super.key});

  @override
  ConsumerState<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends ConsumerState<ExpensesPage> {
  var _range = _Range.today;

  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  var _category = _categories.first;
  var _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  bool get _valid => _name.text.trim().isNotEmpty && (int.tryParse(_amount.text) ?? 0) > 0;

  (DateTime, DateTime) _bounds(DateTime now) => switch (_range) {
        _Range.today => (startOfDay(now), startOfNextDay(now)),
        _Range.week => (startOfWeek(now), startOfWeek(now).add(const Duration(days: 7))),
        _Range.month => (startOfMonth(now), startOfNextMonth(now)),
      };

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref.read(expenseRepositoryProvider).add(
            name: _name.text,
            amount: int.parse(_amount.text),
            category: _category,
            note: _note.text,
            now: ref.read(clockProvider)(),
          );
      _name.clear();
      _amount.clear();
      _note.clear();
      messenger.showSnackBar(const SnackBar(content: Text('Expense saved')));
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Expense e) async {
    final r = await showReasonDialog(
      context,
      title: 'Delete ${e.name}?',
      message: '${formatPeso(e.amount)} is removed from the expenses. It stays in the audit log.',
      confirmLabel: 'Delete',
    );
    if (r == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(expenseRepositoryProvider)
          .delete(id: e.id, reason: r.reason, now: ref.read(clockProvider)());
    } on StateError catch (err) {
      messenger.showSnackBar(SnackBar(content: Text(err.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    // A tab that is hidden does no work: no queries, no timers, no rebuilds.
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox.shrink();
    final c = context.c;
    final now = ref.watch(currentMinuteProvider);
    final bounds = _bounds(now);
    final expenses = ref.watch(expensesRangeProvider(bounds)).valueOrNull ?? const <Expense>[];

    // Group by day, newest day first.
    final byDay = <DateTime, List<Expense>>{};
    for (final e in expenses) {
      byDay.putIfAbsent(startOfDay(e.date), () => []).add(e);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    final list = AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Expanded(
            child: expenses.isEmpty
                ? Center(
                    child: Text('No expenses in this period.',
                        style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)))
                : ListView(
                    children: [
                      for (final d in days) ...[
                        _DayHeader(day: d, today: startOfDay(now), total: byDay[d]!.fold(0, (s, e) => s + e.amount)),
                        for (final e in byDay[d]!) _ExpenseRow(expense: e, onDelete: () => _delete(e)),
                      ],
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Expenses are subtracted from income in the daily report, so the total shows real profit or loss.',
                style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );

    final form = AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add expense', style: condensed(32, color: c.text)),
          const SizedBox(height: 14),
          _label('What was it for?'),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'e.g. Meryenda'),
            onChanged: (_) => setState(() {}),
          ),
          _label('Amount'),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(prefixText: '₱ ', hintText: '0'),
            onChanged: (_) => setState(() {}),
          ),
          _label('Category'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cat in _categories)
                PillChip(
                    label: cat, selected: cat == _category, onTap: () => setState(() => _category = cat)),
            ],
          ),
          _label('Note (optional)'),
          TextField(controller: _note, decoration: const InputDecoration(hintText: 'Add a note')),
          const Spacer(),
          FilledButton(
            onPressed: _valid && !_saving ? _save : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
            child: const Text('Save expense'),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PageTitle('Expenses'),
              const SizedBox(width: 22),
              for (final (r, label) in [
                (_Range.today, 'Today'),
                (_Range.week, 'This week'),
                (_Range.month, 'This month'),
              ]) ...[
                PillChip(label: label, selected: _range == r, onTap: () => setState(() => _range = r)),
                const SizedBox(width: 10),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: list),
                      const SizedBox(width: 22),
                      SizedBox(width: 390, height: box.maxHeight, child: form),
                    ],
                  );
                }
                return Column(
                  children: [
                    Expanded(child: list),
                    const SizedBox(height: 16),
                    SizedBox(height: 460, child: form),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 14),
        child: Text(text, style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: context.c.muted)),
      );
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.today, required this.total});

  final DateTime day;
  final DateTime today;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final label = DateFormat('EEE, MMM d').format(day).toUpperCase();
    final style = TextStyle(
        fontFamily: 'Barlow', fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: c.muted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
      decoration: BoxDecoration(
        color: c.isDark ? c.surface : c.raised.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Text(isSameDay(day, today) ? 'TODAY · $label' : label, style: style),
          const Spacer(),
          Text(formatPeso(total), style: style),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({required this.expense, required this.onDelete});

  final Expense expense;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final free = expense.source == ExpenseSource.complimentary;
    return Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
      child: Row(
        children: [
          Expanded(
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: expense.name,
                  style: TextStyle(
                      fontFamily: 'Barlow', fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
              TextSpan(
                  text: ' · ${expense.category}${expense.note == null ? '' : ' · ${expense.note}'}',
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
            ])),
          ),
          Text(formatPeso(expense.amount), style: condensed(30, color: c.text)),
          SizedBox(
            width: 44,
            child: free
                ? null
                : IconButton(
                    tooltip: 'Delete',
                    icon: Icon(Icons.delete_outline, color: c.muted),
                    onPressed: onDelete,
                  ),
          ),
        ],
      ),
    );
  }
}
