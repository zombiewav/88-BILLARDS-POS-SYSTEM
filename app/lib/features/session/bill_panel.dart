import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/complimentary_repository.dart';
import '../../data/database.dart';
import '../../data/sale_repository.dart';
import '../../domain/enums.dart';
import '../../providers.dart';
import '../common/reason_dialog.dart';
import '../sell/sell_page.dart';
import 'pay_flow.dart';

/// The right-hand bill: every line, Add benta, the total, then Pay / End table.
class BillPanel extends ConsumerWidget {
  const BillPanel({super.key, required this.session, required this.tableLabel});

  final Session session;
  final String tableLabel;

  bool get _running => session.status == SessionStatus.running;
  bool get _open => _running || session.status == SessionStatus.waitingToPay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final lines = _lines(context, ref);

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardTitle('Bill · $tableLabel',
              trailing: '${lines.count} ${lines.count == 1 ? 'line' : 'lines'}'),
          const SizedBox(height: 4),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...lines.widgets,
                  if (_open) ...[
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => SellPage(
                          attachTo: (sessionId: session.id, tableLabel: tableLabel),
                        ),
                      )),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                      icon: const Icon(Icons.add),
                      label: const Text('Add benta'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Total', style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)),
              const Spacer(),
              Text(formatPeso(session.total), style: condensed(68, color: c.text)),
            ],
          ),
          const SizedBox(height: 14),
          ..._actions(context, ref),
        ],
      ),
    );
  }

  ({List<Widget> widgets, int count}) _lines(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final widgets = <Widget>[];
    var count = 0;

    void add(String label, String amount, {VoidCallback? onRemove, String tip = 'Remove one'}) {
      count++;
      widgets.add(_BillLine(label: label, amount: amount, onRemove: onRemove, removeTooltip: tip));
    }

    switch (session.mode) {
      case PlayMode.time:
        add('Table time · ${formatRateLabel(session.baseMinutes ?? 0)}',
            formatPeso(session.baseAmount));
        for (final e in ref.watch(extensionsProvider(session.id)).valueOrNull ?? const []) {
          add('+${formatMinutes(e.minutes)} extension', formatPeso(e.amount));
        }
      case PlayMode.game:
        final games = ref.watch(sessionGamesProvider(session.id)).valueOrNull ?? const [];
        final names = {
          for (final t in ref.watch(gameTypesProvider).valueOrNull ?? const <GameType>[])
            t.id: t.name,
        };
        if (games.isEmpty) {
          widgets.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('No games yet',
                style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
          ));
        }
        for (final g in games) {
          add('${names[g.gameTypeId] ?? 'Game'} × ${g.qty} @ ${formatPeso(g.unitPrice)}',
              formatPeso(g.amount),
              onRemove: _running ? () => _removeGame(context, ref, g) : null);
        }
      case PlayMode.race:
        add('Race table fee', formatPeso(session.baseAmount > 0 ? session.baseAmount : _raceFee(ref)));
    }

    for (final b in ref.watch(sessionBentaProvider(session.id)).valueOrNull ?? const <BentaLine>[]) {
      add('${b.name} × ${b.qty}', formatPeso(b.amount),
          tip: 'Take one off the bill', onRemove: _open ? () => _voidBenta(context, ref, b) : null);
    }

    if (session.mode == PlayMode.race) {
      final free = ref.watch(complimentaryProvider(session.id)).valueOrNull ?? const <ComplimentaryLine>[];
      for (final f in free) {
        widgets.add(_BillLine(
          label: 'Free ${f.name} × ${f.qty}',
          amount: 'not charged',
          muted: true,
          removeTooltip: 'Take back',
          onRemove: _open ? () => _removeFree(context, ref, f) : null,
        ));
      }
    }
    return (widgets: widgets, count: count);
  }

  int _raceFee(WidgetRef ref) => ref.watch(raceDetailProvider(session.id)).valueOrNull?.tableFee ?? 0;

  List<Widget> _actions(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final total = formatPeso(session.total);

    switch (session.status) {
      case SessionStatus.running:
      case SessionStatus.waitingToPay:
        return [
          FilledButton(
            onPressed: () => startPayFlow(context, ref, session: session, tableLabel: tableLabel),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
            child: Text('Pay $total'),
          ),
          const SizedBox(height: 10),
          if (_running)
            OutlinedButton(
              onPressed: () => startEndFlow(context, ref, session: session, tableLabel: tableLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: c.red,
                backgroundColor: Colors.transparent,
                side: BorderSide(color: c.red.withValues(alpha: 0.8), width: 1.4),
                minimumSize: const Size.fromHeight(56),
                textStyle: const TextStyle(fontFamily: 'Barlow', fontSize: 17, fontWeight: FontWeight.w700),
              ),
              child: const Text('End table'),
            )
          else
            TextButton(
              onPressed: () => _markUnpaid(context, ref),
              child: const Text('Customer left without paying'),
            ),
          const SizedBox(height: 8),
          Center(
            child: Text('Pay and End each ask for a second confirmation',
                style: TextStyle(fontFamily: 'Barlow', fontSize: 12, color: c.muted)),
          ),
        ];
      case SessionStatus.paid:
      case SessionStatus.unpaid:
        return [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
            child: const Text('Back to tables'),
          ),
        ];
    }
  }

  /// Runs a repository call and shows its message if it is refused.
  Future<void> _guard(BuildContext context, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  Future<void> _removeGame(BuildContext context, WidgetRef ref, SessionGame game) async {
    final r = await showReasonDialog(
      context,
      title: 'Remove one game?',
      message: 'Use this for a wrong tap. It is recorded in the audit log.',
      confirmLabel: 'Remove',
    );
    if (r == null || !context.mounted) return;
    await _guard(
      context,
      () => ref.read(sessionRepositoryProvider).removeGame(
            sessionId: session.id,
            sessionGameId: game.id,
            reason: r.reason,
            now: ref.read(clockProvider)(),
          ),
    );
  }

  Future<void> _removeFree(BuildContext context, WidgetRef ref, ComplimentaryLine line) async {
    final r = await showReasonDialog(
      context,
      title: 'Take back ${line.name} × ${line.qty}?',
      message: 'The drink goes back to stock and its expense is removed.',
      confirmLabel: 'Take back',
    );
    if (r == null || !context.mounted) return;
    await _guard(
      context,
      () => ref
          .read(complimentaryRepositoryProvider)
          .remove(itemId: line.id, now: ref.read(clockProvider)()),
    );
  }

  Future<void> _voidBenta(BuildContext context, WidgetRef ref, BentaLine line) async {
    final r = await showReasonDialog(
      context,
      title: 'Take off ${line.name}?',
      message: 'One ${line.name} (${formatPeso(line.unitPrice)}) comes off the bill and '
          'goes back to stock. This is recorded as a void.',
      confirmLabel: 'Take off',
    );
    if (r == null || !context.mounted) return;
    await _guard(
      context,
      () => ref.read(voidRepositoryProvider).voidBentaUnit(
            sessionId: session.id,
            productId: line.productId,
            unitPrice: line.unitPrice,
            reason: r.reason,
            now: ref.read(clockProvider)(),
          ),
    );
  }

  Future<void> _markUnpaid(BuildContext context, WidgetRef ref) async {
    final r = await showReasonDialog(
      context,
      title: 'Customer left without paying?',
      message: '$tableLabel is freed and ${formatPeso(session.total)} goes to the Unpaid '
          'list in Reports, to be settled or written off later.',
      confirmLabel: 'Mark unpaid',
    );
    if (r == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(voidRepositoryProvider).markUnpaid(
            sessionId: session.id,
            reason: r.reason,
            now: ref.read(clockProvider)(),
          );
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text('$tableLabel marked unpaid')));
  }
}

class _BillLine extends StatelessWidget {
  const _BillLine({
    required this.label,
    required this.amount,
    this.onRemove,
    this.removeTooltip = 'Remove',
    this.muted = false,
  });

  final String label;
  final String amount;
  final VoidCallback? onRemove;
  final String removeTooltip;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: const BoxConstraints(minHeight: 52),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'Barlow', fontSize: 17, color: muted ? c.muted : c.text)),
          ),
          Text(amount,
              style: TextStyle(
                  fontFamily: 'Barlow',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: muted ? c.muted : c.text)),
          if (onRemove != null)
            IconButton(
              tooltip: removeTooltip,
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.remove_circle_outline, color: c.muted, size: 22),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}
