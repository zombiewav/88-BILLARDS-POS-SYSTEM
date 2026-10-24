import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/slide_to_confirm.dart';
import '../../core/widgets/step_card.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../providers.dart';

/// Pay for a table in two deliberate steps: review and take the cash, then slide
/// to confirm. A running table is stopped and closed by the same step.
/// Pops the page and shows the change when done.
Future<void> startPayFlow(
  BuildContext context,
  WidgetRef ref, {
  required Session session,
  required String tableLabel,
}) async {
  final benta = ref.read(sessionBentaProvider(session.id)).valueOrNull ?? const [];
  final bentaTotal = benta.fold<int>(0, (sum, b) => sum + b.amount);
  final bentaCount = benta.fold<int>(0, (sum, b) => sum + b.qty);
  final tableLabelText = switch (session.mode) {
    PlayMode.time => 'Table time · ${formatRateLabel(session.baseMinutes ?? 0)}',
    PlayMode.game => 'Games',
    PlayMode.race => 'Race table fee',
  };
  final rows = <(String, int)>[
    (tableLabelText, session.total - bentaTotal),
    if (bentaCount > 0) ('Benta · $bentaCount ${bentaCount == 1 ? 'item' : 'items'}', bentaTotal),
  ];

  final cash = await showDialog<int>(
    context: context,
    builder: (_) => _PayReview(
      step: 'STEP 1 OF 2',
      title: 'Pay for $tableLabel?',
      actionLabel: 'Continue',
      rows: rows,
      total: session.total,
    ),
  );
  if (cash == null || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => StepCard(
      step: 'STEP 2 OF 2',
      title: 'Confirm payment of ${formatPeso(session.total)}',
      child: Builder(
        builder: (ctx) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'This records the payment for $tableLabel and cannot be edited afterwards. '
              'Mistakes are corrected with a Void, which is logged.',
              style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: ctx.c.muted),
            ),
            const SizedBox(height: 18),
            SlideToConfirm(
              label: 'Slide to confirm payment',
              onConfirmed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final change = await ref.read(sessionRepositoryProvider).endAndPay(
          sessionId: session.id,
          cashReceived: cash,
          now: ref.read(clockProvider)(),
        );
    navigator.pop();
    messenger.showSnackBar(
        SnackBar(content: Text('$tableLabel paid. Change ${formatPeso(change)}')));
  } on StateError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } on ArgumentError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
  }
}

/// Step 1 of paying: the lines, the cash received and the change.
class _PayReview extends StatefulWidget {
  const _PayReview({
    required this.step,
    required this.title,
    required this.actionLabel,
    required this.rows,
    required this.total,
  });

  final String step;
  final String title;
  final String actionLabel;
  final List<(String, int)> rows;
  final int total;

  @override
  State<_PayReview> createState() => _PayReviewState();
}

class _PayReviewState extends State<_PayReview> {
  final _cash = TextEditingController();

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  int get _received => int.tryParse(_cash.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final enough = _received >= widget.total;
    final quick = <int>{100, 200, 500, 1000}.where((v) => v >= widget.total);

    Widget row(String label, Widget value) => Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
              value,
            ],
          ),
        );

    Text money(int v) => Text(formatPeso(v),
        style: TextStyle(
            fontFamily: 'Barlow', fontSize: 16, fontWeight: FontWeight.w700, color: c.text));

    return StepCard(
      step: widget.step,
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final r in widget.rows) row(r.$1, money(r.$2)),
          row(
            'Cash received',
            SizedBox(
              width: 130,
              child: TextField(
                controller: _cash,
                autofocus: true,
                textAlign: TextAlign.right,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  prefixText: '₱ ',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickChip(label: 'Exact', onTap: () => setState(() => _cash.text = '${widget.total}')),
              for (final v in quick)
                _QuickChip(label: formatPeso(v), onTap: () => setState(() => _cash.text = '$v')),
            ],
          ),
          row('Change', money(enough ? _received - widget.total : 0)),
          Container(
            padding: const EdgeInsets.only(top: 6, bottom: 14),
            decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Total',
                    style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)),
                const Spacer(),
                Text(formatPeso(widget.total), style: condensed(60, color: c.text)),
              ],
            ),
          ),
          FilledButton(
            onPressed: enough ? () => Navigator.pop(context, _received) : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: Text(widget.actionLabel),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }
}

/// Cash entry for a walk-in sale (one step, no table). Pops the cash received.
class PayCashDialog extends StatelessWidget {
  const PayCashDialog({super.key, required this.title, required this.total});

  final String title;
  final int total;

  @override
  Widget build(BuildContext context) {
    return _PayReview(
      step: 'WALK-IN SALE',
      title: title,
      actionLabel: 'Take payment',
      rows: const [],
      total: total,
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.raised,
      shape: StadiumBorder(side: BorderSide(color: c.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'Barlow', fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
        ),
      ),
    );
  }
}

/// End a table in two steps. The clock stops and the bill waits to be paid.
Future<void> startEndFlow(
  BuildContext context,
  WidgetRef ref, {
  required Session session,
  required String tableLabel,
}) async {
  final now = ref.read(clockProvider)();
  final end = session.endsAt;
  final early = end != null && end.isAfter(now) ? end.difference(now).inMinutes : 0;

  final go = await showDialog<bool>(
    context: context,
    builder: (_) => StepCard(
      danger: true,
      step: 'STEP 1 OF 2',
      title: 'End $tableLabel now?',
      child: Builder(
        builder: (ctx) {
          final c = ctx.c;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                early > 0
                    ? 'The timer stops and the bill waits to be paid. Ending $early min early '
                        'does not refund time.'
                    : 'The timer stops and the bill waits to be paid.',
                style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.isDark ? c.coralTint : c.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.red.withValues(alpha: 0.6)),
                ),
                child: Text(
                  'Unpaid balance of ${formatPeso(session.total)}. Pay first, or end and '
                  'keep it waiting to be paid.',
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.isDark ? c.text : c.red),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: c.red,
                  foregroundColor: c.isDark ? c.bg : Colors.white,
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text('Yes, end table'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Keep playing'),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text('Step 2: type the table name ($tableLabel) to finish',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Barlow', fontSize: 12, color: c.muted)),
              ),
            ],
          );
        },
      ),
    ),
  );
  if (go != true || !context.mounted) return;

  final finished = await showDialog<bool>(
    context: context,
    builder: (_) => _EndConfirm(tableLabel: tableLabel),
  );
  if (finished != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(sessionRepositoryProvider)
        .endTable(sessionId: session.id, now: ref.read(clockProvider)());
  } on StateError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  }
}

/// Step 2 of ending: type the table name, so a stray tap can't end a table.
class _EndConfirm extends StatefulWidget {
  const _EndConfirm({required this.tableLabel});

  final String tableLabel;

  @override
  State<_EndConfirm> createState() => _EndConfirmState();
}

class _EndConfirmState extends State<_EndConfirm> {
  final _input = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _finish() {
    if (_input.text.trim().toLowerCase() == widget.tableLabel.toLowerCase()) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Type ${widget.tableLabel} to end this table.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return StepCard(
      danger: true,
      step: 'STEP 2 OF 2',
      title: 'Finish ending ${widget.tableLabel}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Type the table name (${widget.tableLabel}) to finish.',
              style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
          const SizedBox(height: 14),
          TextField(
            controller: _input,
            autofocus: true,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _finish(),
            decoration: InputDecoration(
              hintText: widget.tableLabel,
              errorText: _error,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _input.text.trim().isEmpty ? null : _finish,
            style: FilledButton.styleFrom(
              backgroundColor: c.red,
              foregroundColor: c.isDark ? c.bg : Colors.white,
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('End table'),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
