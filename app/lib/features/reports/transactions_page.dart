import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../core/day.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../data/history_repository.dart';
import '../../data/void_repository.dart';
import '../../domain/enums.dart';
import '../../providers.dart';
import '../auth/owner_pin_dialog.dart' show askOwnerApproval, ownerPinSetProvider;
import '../auth/pin_entry.dart';
import '../common/reason_dialog.dart';
import '../session/pay_flow.dart' show PayCashDialog;

/// One paid thing on the list: a table bill or a walk-in sale.
class _Txn {
  const _Txn({
    required this.id,
    required this.isSession,
    required this.ref,
    required this.where,
    required this.paidAt,
    required this.amount,
    this.session,
  });

  final String id;
  final bool isSession;
  final String? ref;
  final String where;
  final DateTime paidAt;
  final int amount;
  final Session? session;
}

enum _Tab { paid, unpaid }

/// Voids and log: every paid bill and sale for a day, with refunds that need an
/// Owner PIN, plus the Unpaid list.
class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  DateTime? _day;
  var _tab = _Tab.paid;
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = ref.watch(currentMinuteProvider);
    final today = startOfDay(now);
    final day = _day ?? today;
    final unpaidCount = ref.watch(unpaidProvider).valueOrNull?.length ?? 0;

    final bills = ref.watch(paidSessionsProvider(day)).valueOrNull ?? const <PaidSession>[];
    final sales = ref.watch(walkInSalesProvider(day)).valueOrNull ?? const <WalkInSale>[];
    final txns = [
      for (final b in bills)
        _Txn(
          id: b.session.id,
          isSession: true,
          ref: b.session.ref,
          where: b.tableLabel,
          paidAt: b.payment.paidAt,
          amount: b.payment.amount,
          session: b.session,
        ),
      for (final s in sales)
        _Txn(
          id: s.sale.id,
          isSession: false,
          ref: s.sale.ref,
          where: 'Walk-in',
          paidAt: s.payment.paidAt,
          amount: s.payment.amount,
        ),
    ]..sort((a, b) => a.paidAt.compareTo(b.paidAt));
    final selected = txns.where((t) => t.id == _selectedId).firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.chevron_left),
                label: const Text('Reports'),
              ),
              const SizedBox(width: 16),
              PageTitle('Transactions',
                  note: isSameDay(day, today)
                      ? 'Today · ${DateFormat('EEE, MMM d').format(day)}'
                      : DateFormat('EEE, MMM d').format(day)),
              const SizedBox(width: 20),
              PillChip(
                  label: 'Paid', selected: _tab == _Tab.paid, onTap: () => setState(() => _tab = _Tab.paid)),
              const SizedBox(width: 8),
              PillChip(
                label: unpaidCount == 0 ? 'Unpaid' : 'Unpaid $unpaidCount',
                selected: _tab == _Tab.unpaid,
                tone: unpaidCount > 0 ? c.coral : null,
                onTap: () => setState(() => _tab = _Tab.unpaid),
              ),
              const Spacer(),
              if (_tab == _Tab.paid) ...[
                OutlinedButton(
                  onPressed: () => setState(() {
                    _day = null;
                    _selectedId = null;
                  }),
                  child: const Text('Today'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: DateTime(2024),
                      lastDate: today,
                    );
                    if (picked != null) {
                      setState(() {
                        _day = startOfDay(picked);
                        _selectedId = null;
                      });
                    }
                  },
                  child: const Text('Pick date'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: _tab == _Tab.unpaid
                ? const _UnpaidList()
                : LayoutBuilder(
                    builder: (context, box) {
                      final table = _Table(
                        txns: txns,
                        selectedId: _selectedId,
                        onSelect: (id) => setState(() => _selectedId = id),
                      );
                      final panel = _VoidPanel(
                        key: ValueKey(selected?.id),
                        txn: selected,
                      );
                      if (box.maxWidth >= 900) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: table),
                            const SizedBox(width: 22),
                            SizedBox(width: 390, height: box.maxHeight, child: panel),
                          ],
                        );
                      }
                      return Column(children: [
                        Expanded(child: table),
                        const SizedBox(height: 16),
                        SizedBox(height: 640, child: panel),
                      ]);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.txns, required this.selectedId, required this.onSelect});

  final List<_Txn> txns;
  final String? selectedId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final head = TextStyle(
        fontFamily: 'Barlow', fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.muted);

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            decoration: BoxDecoration(
              color: c.isDark ? c.surface : c.raised.withValues(alpha: 0.5),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('TIME', style: head)),
                Expanded(flex: 3, child: Text('REF', style: head)),
                Expanded(flex: 3, child: Text('WHERE', style: head)),
                Expanded(flex: 8, child: Text('DETAILS', style: head)),
                Expanded(flex: 3, child: Text('AMOUNT', textAlign: TextAlign.right, style: head)),
                Expanded(flex: 3, child: Text('STATUS', textAlign: TextAlign.right, style: head)),
              ],
            ),
          ),
          Expanded(
            child: txns.isEmpty
                ? Center(
                    child: Text('Nothing paid on this day.',
                        style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)))
                : ListView(
                    children: [
                      for (final t in txns)
                        _TxnRow(
                          txn: t,
                          selected: t.id == selectedId,
                          onTap: () => onSelect(t.id == selectedId ? null : t.id),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Voided rows stay in the list and in the report, with who voided them and why. '
                'Nothing is ever deleted.',
                style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a transaction was: "Time · 1 hr + Royal × 1".
String _details(WidgetRef ref, _Txn t, List<VoidableLine> lines) {
  if (!t.isSession) return lines.map((l) => l.label).join(' + ');
  final s = t.session!;
  final head = switch (s.mode) {
    PlayMode.time => 'Time · ${formatRateLabel(s.baseMinutes ?? 0)}',
    PlayMode.game => () {
        final games = ref.watch(sessionGamesProvider(s.id)).valueOrNull ?? const [];
        final names = {
          for (final g in ref.watch(gameTypesProvider).valueOrNull ?? const <GameType>[]) g.id: g.name,
        };
        final text = games.map((g) => '${names[g.gameTypeId] ?? 'Game'} × ${g.qty}').join(', ');
        return text.isEmpty ? 'Game' : 'Game · $text';
      }(),
    PlayMode.race => 'Race',
  };
  final items = lines.where((l) => !l.isTable).map((l) => l.label);
  return [head, ...items].join(' + ');
}

class _TxnRow extends ConsumerWidget {
  const _TxnRow({required this.txn, required this.selected, required this.onTap});

  final _Txn txn;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final lines = (txn.isSession
                ? ref.watch(sessionLinesProvider(txn.id))
                : ref.watch(saleLinesProvider(txn.id)))
            .valueOrNull ??
        const <VoidableLine>[];
    final allVoided = lines.isNotEmpty && lines.every((l) => l.voided);
    final someVoided = lines.any((l) => l.voided);

    final (status, tone) = selected
        ? ('Selected', c.gold)
        : allVoided
            ? ('Voided', c.red)
            : someVoided
                ? ('Part voided', c.coral)
                : ('Paid', c.green);
    final body = TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted);

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: selected ? c.selected.withValues(alpha: c.isDark ? 0.5 : 0.7) : null,
          border: Border(
            bottom: BorderSide(color: c.border),
            left: BorderSide(color: selected ? c.red : Colors.transparent, width: 3),
          ),
        ),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(formatClock(txn.paidAt), style: body)),
            Expanded(flex: 3, child: Text(txn.ref == null ? '' : '#${txn.ref}', style: body)),
            Expanded(
                flex: 3,
                child: Text(txn.where,
                    style: TextStyle(
                        fontFamily: 'Barlow', fontSize: 16, fontWeight: FontWeight.w700, color: c.text))),
            Expanded(
              flex: 8,
              child: Text(_details(ref, txn, lines),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.text)),
            ),
            Expanded(
              flex: 3,
              child: Text(
                formatPeso(txn.amount),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: 'Barlow',
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: allVoided ? c.muted : c.text,
                  decoration: allVoided ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(status,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      fontFamily: 'Barlow', fontSize: 14, fontWeight: FontWeight.w700, color: tone)),
            ),
          ],
        ),
      ),
    );
  }
}

const _reasons = ['Wrong item', 'Customer cancelled', 'Cashier mistake', 'Other'];

/// Right-hand panel: choose lines, a reason, an Owner PIN, then Void.
class _VoidPanel extends ConsumerStatefulWidget {
  const _VoidPanel({super.key, required this.txn});

  final _Txn? txn;

  @override
  ConsumerState<_VoidPanel> createState() => _VoidPanelState();
}

class _VoidPanelState extends ConsumerState<_VoidPanel> {
  /// Keys the user un-ticked (everything else that can be voided is ticked).
  final _unchecked = <String>{};
  String? _reason;
  final _other = TextEditingController();
  StaffMember? _approver;
  var _busy = false;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String? get _reasonText {
    if (_reason == null) return null;
    if (_reason == 'Other') return _other.text.trim().isEmpty ? null : _other.text.trim();
    return _reason;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = widget.txn;

    if (t == null) {
      return AppCard(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('Tap a transaction to void it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)),
        ),
      );
    }

    final lines = (t.isSession ? ref.watch(sessionLinesProvider(t.id)) : ref.watch(saleLinesProvider(t.id)))
            .valueOrNull ??
        const <VoidableLine>[];
    final open = lines.where((l) => !l.voided).toList();
    final chosen = open.where((l) => !_unchecked.contains(l.key)).toList();
    final amount = chosen.fold<int>(0, (s, l) => s + l.amount);
    // Once an Owner PIN is set, voids need it; until then they go through on a reason alone.
    final needsPin = ref.watch(ownerPinSetProvider);
    final approved = !needsPin || _approver != null;
    final canVoid = chosen.isNotEmpty && _reasonText != null && approved && !_busy;

    return AppCard(
      padding: const EdgeInsets.all(22),
      borderColor: c.red.withValues(alpha: 0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Void #${t.ref ?? '-'}', style: condensed(34, color: c.red)),
              const Spacer(),
              Text('${t.where} · ${formatClock(t.paidAt)}',
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final l in lines)
                    Container(
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
                      child: Row(
                        children: [
                          Checkbox(
                            value: !l.voided && !_unchecked.contains(l.key),
                            onChanged: l.voided
                                ? null
                                : (v) => setState(() {
                                      if (v == true) {
                                        _unchecked.remove(l.key);
                                      } else {
                                        _unchecked.add(l.key);
                                      }
                                    }),
                          ),
                          Expanded(
                            child: Text(l.label,
                                style: TextStyle(
                                    fontFamily: 'Barlow',
                                    fontSize: 16,
                                    color: l.voided ? c.muted : c.text)),
                          ),
                          Text(l.voided ? 'voided' : formatPeso(l.amount),
                              style: TextStyle(
                                  fontFamily: 'Barlow',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: l.voided ? c.red : c.text)),
                        ],
                      ),
                    ),
                  if (open.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text('Reason (required)',
                        style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final r in _reasons)
                          PillChip(
                            label: r,
                            selected: _reason == r,
                            tone: _reason == r ? c.red : null,
                            onTap: () => setState(() => _reason = r),
                          ),
                      ],
                    ),
                    if (_reason == 'Other') ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _other,
                        decoration: const InputDecoration(hintText: 'Type the reason'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (!needsPin)
                      const SizedBox.shrink()
                    else if (_approver == null) ...[
                      Text('Owner 6-digit PIN to approve',
                          style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted)),
                      const SizedBox(height: 10),
                      Center(
                        child: PinEntry(
                          keyHeight: 50,
                          verify: (pin) => ref
                              .read(staffRepositoryProvider)
                              .approveAsOwner(pin, now: ref.read(clockProvider)()),
                          onSuccess: (owner) => setState(() => _approver = owner),
                        ),
                      ),
                    ] else
                      Row(
                        children: [
                          Icon(Icons.verified_outlined, color: c.green),
                          const SizedBox(width: 10),
                          Text('Approved by ${_approver!.name}',
                              style: TextStyle(
                                  fontFamily: 'Barlow',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: c.green)),
                          const Spacer(),
                          TextButton(
                              onPressed: () => setState(() => _approver = null),
                              child: const Text('Change')),
                        ],
                      ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: canVoid ? () => _void(t, chosen) : null,
            style: FilledButton.styleFrom(
              backgroundColor: c.red,
              foregroundColor: c.isDark ? c.bg : Colors.white,
              minimumSize: const Size.fromHeight(58),
            ),
            child: Text(open.isEmpty ? 'Already voided' : 'Void ${formatPeso(amount)}'),
          ),
        ],
      ),
    );
  }

  Future<void> _void(_Txn t, List<VoidableLine> chosen) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final refunded = await ref.read(voidRepositoryProvider).voidLines(
            sessionId: t.isSession ? t.id : null,
            saleId: t.isSession ? null : t.id,
            keys: [for (final l in chosen) l.key],
            reason: _reasonText!,
            approvedBy: _approver?.name ?? 'Device',
            now: ref.read(clockProvider)(),
          );
      if (!mounted) return;
      setState(() {
        _unchecked.clear();
        _reason = null;
        _other.clear();
        _approver = null;
      });
      messenger.showSnackBar(SnackBar(content: Text('Voided ${formatPeso(refunded)}')));
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Bills where the customer left: settle later or write off with Owner approval.
class _UnpaidList extends ConsumerWidget {
  const _UnpaidList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final bills = ref.watch(unpaidProvider).valueOrNull ?? const <UnpaidBill>[];
    if (bills.isEmpty) {
      return AppCard(
        child: Center(
          child: Text('No unpaid bills.',
              style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)),
        ),
      );
    }
    return ListView.separated(
      itemCount: bills.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final b = bills[i];
        final ended = b.session.endedAt ?? b.session.startedAt;
        return AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.money_off_outlined, color: c.coral),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${b.tableLabel} · ${b.session.mode.label}',
                        style: TextStyle(
                            fontFamily: 'Barlow',
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: c.text)),
                    Text(
                      [
                        '${ended.month}/${ended.day} ${formatClock(ended)}',
                        if (b.session.note != null) b.session.note!,
                      ].join(' · '),
                      style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted),
                    ),
                  ],
                ),
              ),
              Text(formatPeso(b.session.total), style: condensed(34, color: c.text)),
              const SizedBox(width: 20),
              FilledButton(
                onPressed: () => _settle(context, ref, b),
                style: FilledButton.styleFrom(minimumSize: const Size(110, 48)),
                child: const Text('Settle'),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: () => _writeOff(context, ref, b),
                child: const Text('Write off'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _settle(BuildContext context, WidgetRef ref, UnpaidBill b) async {
    final cash = await showDialog<int>(
      context: context,
      builder: (_) =>
          PayCashDialog(title: 'Settle ${b.tableLabel}: ${formatPeso(b.session.total)}', total: b.session.total),
    );
    if (cash == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final change = await ref.read(voidRepositoryProvider).settleUnpaid(
            sessionId: b.session.id,
            cashReceived: cash,
            now: ref.read(clockProvider)(),
          );
      messenger.showSnackBar(SnackBar(content: Text('Settled. Change ${formatPeso(change)}')));
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _writeOff(BuildContext context, WidgetRef ref, UnpaidBill b) async {
    final approver = await askOwnerApproval(
      context,
      ref,
      title: 'Write off ${b.tableLabel}',
      message: 'An Owner must approve writing off ${formatPeso(b.session.total)}.',
    );
    if (approver == null || !context.mounted) return;
    final r = await showReasonDialog(
      context,
      title: 'Write off ${b.tableLabel}?',
      message: '${formatPeso(b.session.total)} will not be collected. The record stays in the void log.',
      confirmLabel: 'Write off',
    );
    if (r == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(voidRepositoryProvider).writeOffUnpaid(
            sessionId: b.session.id,
            reason: '${r.reason} (approved by $approver)',
            now: ref.read(clockProvider)(),
          );
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
