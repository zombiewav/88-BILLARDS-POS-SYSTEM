import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../domain/table_status.dart';
import '../../providers.dart';
import '../tables/table_card.dart' show timeUsed;
import 'bill_panel.dart';
import 'complimentary_dialog.dart';
import 'extend_dialog.dart';

/// One table's session: timer, mode controls and the bill.
class SessionPage extends ConsumerWidget {
  const SessionPage({super.key, required this.sessionId, required this.tableLabel});

  final String sessionId;
  final String tableLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider(sessionId));

    return session.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load session: $e')),
      data: (s) {
        if (s == null) return const Center(child: Text('Session not found'));
        return _Body(session: s, tableLabel: tableLabel);
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.session, required this.tableLabel});

  final Session session;
  final String tableLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final now = ref.watch(currentTimeProvider);
    final alert = ref.watch(alertMinutesProvider);
    final status = tableStatusFor(
      sessionStatus: session.status,
      endsAt: session.endsAt,
      now: now,
      alertMinutes: alert,
    );
    final end = session.endsAt;
    final running = session.status == SessionStatus.running;

    final (pillLabel, pillColor) = switch (session.status) {
      SessionStatus.paid => ('Paid', c.green),
      SessionStatus.unpaid => ('Unpaid', c.red),
      _ => (status.label, status.colorIn(c)),
    };

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (running && end != null && status == TableStatus.endingSoon) ...[
          Banner2(
            icon: Icons.notifications_none_rounded,
            color: c.coral,
            text: remainingTime(end, now) == Duration.zero
                ? '$tableLabel time is up (${formatClock(end)}). Extend the time or end the table.'
                : '$tableLabel ends in ${_minutesLeft(end, now)} min (${formatClock(end)}). '
                    'Extend the time or end the table.',
          ),
          const SizedBox(height: 16),
        ],
        _TimerCard(session: session, status: status, now: now),
        if (running && session.mode == PlayMode.time) ...[
          const SizedBox(height: 16),
          _ExtendCard(session: session),
        ],
        if (running && session.mode == PlayMode.game) ...[
          const SizedBox(height: 16),
          _GamesCard(session: session),
        ],
        if (session.mode == PlayMode.race) ...[
          const SizedBox(height: 16),
          _RaceCard(session: session),
        ],
      ],
    );

    final bill = BillPanel(session: session, tableLabel: tableLabel);

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
                label: const Text('Tables'),
              ),
              const SizedBox(width: 16),
              Text(tableLabel, style: condensed(52, color: c.text)),
              const SizedBox(width: 14),
              StatusPill(label: pillLabel, color: pillColor),
              const Spacer(),
              Text(
                [
                  if (session.ref != null) 'Session #${session.ref}',
                  if (session.openedBy != null) 'opened by ${session.openedBy}',
                ].join(' · '),
                style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted),
              ),
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
                      Expanded(child: SingleChildScrollView(child: left)),
                      const SizedBox(width: 22),
                      SizedBox(width: 400, height: box.maxHeight, child: bill),
                    ],
                  );
                }
                return SingleChildScrollView(
                  child: Column(
                    children: [left, const SizedBox(height: 20), SizedBox(height: 620, child: bill)],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int _minutesLeft(DateTime end, DateTime now) =>
      (end.difference(now).inSeconds / 60).ceil().clamp(1, 9999);
}

/// The big countdown (or elapsed clock) with its progress bar and start/end/elapsed.
class _TimerCard extends ConsumerWidget {
  const _TimerCard({required this.session, required this.status, required this.now});

  final Session session;
  final TableStatus status;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final end = session.endsAt;
    final live = session.status == SessionStatus.running;
    final stopAt = session.endedAt ?? now;
    final used = live ? timeUsed(session, now) : null;
    final accent = live && status == TableStatus.endingSoon ? c.coral : c.text;

    final tag = switch (session.mode) {
      PlayMode.time => 'TIME MODE',
      PlayMode.game => 'GAME MODE',
      PlayMode.race => 'RACE MODE',
    };
    final race = session.mode == PlayMode.race
        ? ref.watch(raceDetailProvider(session.id)).valueOrNull
        : null;
    final extensions = session.mode == PlayMode.time
        ? ref.watch(extensionsProvider(session.id)).valueOrNull ?? const []
        : const <SessionExtension>[];
    final paidMinutes = (session.baseMinutes ?? 0) + extensions.fold<int>(0, (s, e) => s + e.minutes);

    final detail = switch (session.mode) {
      PlayMode.time => '${formatRateLabel(session.baseMinutes ?? 0)} block',
      PlayMode.game => 'open time, price per game',
      PlayMode.race => 'Race to ${race?.raceTo ?? '-'}',
    };

    final String big;
    final String unit;
    if (live && end != null) {
      big = formatCountdown(remainingTime(end, now));
      unit = 'remaining';
    } else if (live) {
      big = formatCountdown(now.difference(session.startedAt));
      unit = 'elapsed';
    } else {
      big = formatCountdown(stopAt.difference(session.startedAt));
      unit = 'played';
    }

    Widget stat(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
            Text(value, style: condensed(40, color: c.text)),
          ],
        );

    return AppCard(
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: c.goldTint,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(tag,
                    style: TextStyle(
                        fontFamily: 'Barlow',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: c.gold)),
              ),
              const SizedBox(width: 14),
              Text(detail, style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
              const Spacer(),
              if (session.mode == PlayMode.time)
                Text.rich(TextSpan(children: [
                  TextSpan(
                      text: 'Paid time ',
                      style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
                  TextSpan(
                      text: formatMinutes(paidMinutes),
                      style: TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.text)),
                ])),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(big, style: condensed(170, color: accent)),
                ),
              ),
              const SizedBox(width: 12),
              Text(unit, style: TextStyle(fontFamily: 'Barlow', fontSize: 22, color: c.muted)),
            ],
          ),
          if (used != null) ...[
            const SizedBox(height: 6),
            ThinBar(value: used, color: status == TableStatus.endingSoon ? c.coral : c.blue, height: 10),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              stat('Started', formatClock(session.startedAt)),
              const SizedBox(width: 44),
              stat(session.status == SessionStatus.running ? 'Ends' : 'Ended',
                  live ? (end == null ? 'Open' : formatClock(end)) : formatClock(stopAt)),
              const SizedBox(width: 44),
              stat('Elapsed', formatCountdown(stopAt.difference(session.startedAt))),
            ],
          ),
        ],
      ),
    );
  }
}

/// Extend time: the first two rates and a custom amount.
class _ExtendCard extends ConsumerWidget {
  const _ExtendCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final rates = (ref.watch(timeRatesProvider).valueOrNull ?? const <TimeRate>[]).take(2).toList();

    Future<void> extend(int minutes, int amount) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref.read(sessionRepositoryProvider).extend(
              sessionId: session.id,
              minutes: minutes,
              amount: amount,
              now: ref.read(clockProvider)(),
            );
      } on StateError catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    }

    Widget button(String title, String sub, VoidCallback onTap, {bool goldSub = false}) {
      return Expanded(
        child: Material(
          color: c.raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: c.border),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: onTap,
            child: SizedBox(
              height: 74,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: condensed(30, color: c.text)),
                  Text(sub,
                      style: TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 13,
                          fontWeight: goldSub ? FontWeight.w700 : FontWeight.w500,
                          color: goldSub ? c.gold : c.muted)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Extend time',
                  style: TextStyle(
                      fontFamily: 'Barlow', fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
              const Spacer(),
              Flexible(
                child: Text('Extra time is added to the bill and the end time moves',
                    style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              for (final r in rates) ...[
                button('+ ${formatMinutes(r.minutes)}', '+${formatPeso(r.price)}',
                    () => extend(r.minutes, r.price),
                    goldSub: true),
                const SizedBox(width: 14),
              ],
              button('Custom', 'enter minutes', () async {
                final choice = await showDialog<ExtendChoice>(
                  context: context,
                  builder: (_) => const ExtendDialog(),
                );
                if (choice != null) await extend(choice.minutes, choice.amount);
              }),
            ],
          ),
        ],
      ),
    );
  }
}

/// Game mode: tap a game when it finishes.
class _GamesCard extends ConsumerWidget {
  const _GamesCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final types = ref.watch(gameTypesProvider).valueOrNull ?? const <GameType>[];

    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Game finished?',
                  style: TextStyle(
                      fontFamily: 'Barlow', fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(width: 12),
              Text('Tap the game to add it to the bill',
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final t in types)
                SizedBox(
                  width: 170,
                  child: Material(
                    color: c.raised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: c.border),
                    ),
                    child: InkWell(
                      customBorder:
                          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      onTap: () => ref.read(sessionRepositoryProvider).addGame(
                            sessionId: session.id,
                            gameTypeId: t.id,
                            now: ref.read(clockProvider)(),
                          ),
                      child: SizedBox(
                        height: 84,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text('+ ${t.name}', style: condensed(28, color: c.text)),
                            Text(formatPeso(t.pricePerGame),
                                style: TextStyle(
                                    fontFamily: 'Barlow',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: c.gold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Race: the money split, and free drinks.
class _RaceCard extends ConsumerWidget {
  const _RaceCard({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final race = ref.watch(raceDetailProvider(session.id)).valueOrNull;
    final open = session.status == SessionStatus.running ||
        session.status == SessionStatus.waitingToPay;

    Widget stat(String label, String value, {Color? color}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
              Text(value, style: condensed(36, color: color ?? c.text)),
            ],
          ),
        );

    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Race money',
              style: TextStyle(
                  fontFamily: 'Barlow', fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
          const SizedBox(height: 12),
          if (race != null)
            Row(
              children: [
                stat('Race total', formatPeso(race.betTotal)),
                stat('Bet money (not hall income)', formatPeso(race.betTotal - race.tableFee)),
                stat('Table fee', formatPeso(race.tableFee), color: c.gold),
              ],
            ),
          if (open) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _giveFree(context, ref),
              icon: const Icon(Icons.card_giftcard_outlined),
              label: const Text('Give free drink'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _giveFree(BuildContext context, WidgetRef ref) async {
    final choice = await showDialog<ComplimentaryChoice>(
      context: context,
      builder: (_) => const ComplimentaryDialog(),
    );
    if (choice == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(complimentaryRepositoryProvider).add(
            sessionId: session.id,
            productId: choice.productId,
            qty: choice.qty,
            note: choice.note,
            now: ref.read(clockProvider)(),
          );
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

