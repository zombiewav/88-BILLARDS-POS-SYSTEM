import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../data/session_repository.dart';
import '../../domain/enums.dart';
import '../../domain/table_status.dart';
import '../../providers.dart';

/// Status of a table row right now.
TableStatus statusOfRow(TableWithSession row, DateTime now, int alertMinutes) {
  final s = row.session;
  return tableStatusFor(
    sessionStatus: s?.status,
    endsAt: s?.endsAt,
    now: now,
    alertMinutes: alertMinutes,
  );
}

/// Short description of what is being played, for cards and map tiles.
String modeSummary(WidgetRef ref, Session s) {
  switch (s.mode) {
    case PlayMode.time:
      return 'Time · ${formatMinutes(s.baseMinutes ?? 0)}';
    case PlayMode.game:
      final games = ref.watch(sessionGamesProvider(s.id)).valueOrNull ?? const [];
      final n = games.fold<int>(0, (sum, g) => sum + g.qty);
      return 'Game · $n ${n == 1 ? 'game' : 'games'}';
    case PlayMode.race:
      final race = ref.watch(raceDetailProvider(s.id)).valueOrNull;
      return race == null ? 'Race' : 'Race to ${race.raceTo}';
  }
}

/// How much of the paid time is used (0 to 1), or null for open-ended sessions.
double? timeUsed(Session s, DateTime now) {
  final end = s.endsAt;
  if (end == null) return null;
  final total = end.difference(s.startedAt).inSeconds;
  if (total <= 0) return 1;
  return now.difference(s.startedAt).inSeconds / total;
}

class TableCard extends ConsumerWidget {
  const TableCard({
    super.key,
    required this.row,
    required this.now,
    required this.alertMinutes,
    required this.onTap,
  });

  final TableWithSession row;
  final DateTime now;
  final int alertMinutes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final session = row.session;
    final status = statusOfRow(row, now, alertMinutes);
    final color = status.colorIn(c);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
      borderColor: status == TableStatus.endingSoon ? c.coral : null,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(row.table.label, style: condensed(44, color: c.text)),
              const Spacer(),
              StatusPill(label: status.label, color: color),
            ],
          ),
          if (session == null) ...[
            const Spacer(),
            Center(
              child: Column(
                children: [
                  Text('Table is available',
                      style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)),
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: onTap,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(150, 50),
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                    ),
                    child: const Text('Start game'),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ] else
            Expanded(child: _SessionBody(session: session, status: status, now: now, onOpen: onTap)),
        ],
      ),
    );
  }
}

class _SessionBody extends ConsumerWidget {
  const _SessionBody({
    required this.session,
    required this.status,
    required this.now,
    required this.onOpen,
  });

  final Session session;
  final TableStatus status;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final color = status.colorIn(c);
    final waiting = status == TableStatus.waitingToPay;
    final end = session.endsAt;
    final used = timeUsed(session, now);

    final String big;
    final String unit;
    if (waiting) {
      big = formatClock(session.endedAt ?? now);
      unit = 'ended';
    } else if (end != null) {
      big = formatCountdown(remainingTime(end, now));
      unit = 'remaining';
    } else {
      big = formatCountdown(now.difference(session.startedAt));
      unit = 'elapsed';
    }

    Widget startEnd() {
      final muted = TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted);
      final strong = TextStyle(
          fontFamily: 'Barlow', fontSize: 13, fontWeight: FontWeight.w700, color: c.text);
      return Text.rich(TextSpan(children: [
        TextSpan(text: 'Start ', style: muted),
        TextSpan(text: formatClock(session.startedAt), style: strong),
        TextSpan(text: '    End ', style: muted),
        TextSpan(text: end == null ? 'Open' : formatClock(end), style: strong),
      ]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        Text(modeSummary(ref, session),
            style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(big,
                    style: condensed(waiting ? 48 : 62,
                        color: waiting ? c.text : (status == TableStatus.endingSoon ? color : c.text))),
              ),
            ),
            const SizedBox(width: 8),
            Text(unit, style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
          ],
        ),
        if (!waiting && used != null) ...[
          const SizedBox(height: 4),
          ThinBar(value: used, color: color, height: 6),
        ],
        const SizedBox(height: 8),
        if (!waiting) startEnd(),
        const Spacer(),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(formatPeso(session.total), style: condensed(38, color: c.text)),
            const Spacer(),
            OutlinedButton(
              onPressed: onOpen,
              style: OutlinedButton.styleFrom(minimumSize: const Size(88, 46)),
              child: const Text('Open'),
            ),
          ],
        ),
      ],
    );
  }
}
