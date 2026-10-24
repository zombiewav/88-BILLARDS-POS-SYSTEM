import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../core/day.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/report_repository.dart';
import '../../providers.dart';
import 'transactions_page.dart';

/// Daily, weekly and monthly report: the notebook page, computed.
class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  var _period = ReportPeriod.daily;
  DateTime? _anchor;

  DateTime _step(DateTime a, int dir) => switch (_period) {
        ReportPeriod.daily => DateTime(a.year, a.month, a.day + dir),
        ReportPeriod.weekly => DateTime(a.year, a.month, a.day + 7 * dir),
        ReportPeriod.monthly => DateTime(a.year, a.month + dir, 1),
      };

  String _label(DateTime a, DateTime today) {
    switch (_period) {
      case ReportPeriod.daily:
        return isSameDay(a, today) ? 'Today' : DateFormat('EEE, MMM d').format(a);
      case ReportPeriod.weekly:
        final from = startOfWeek(a);
        final to = from.add(const Duration(days: 6));
        return '${DateFormat('MMM d').format(from)} – ${DateFormat('MMM d').format(to)}';
      case ReportPeriod.monthly:
        return DateFormat('MMMM yyyy').format(a);
    }
  }

  /// The newest day the arrows may reach: the period that contains today.
  bool _atNewest(DateTime a, DateTime today) => switch (_period) {
        ReportPeriod.daily => !a.isBefore(startOfDay(today)),
        ReportPeriod.weekly => !startOfWeek(a).isBefore(startOfWeek(today)),
        ReportPeriod.monthly => !startOfMonth(a).isBefore(startOfMonth(today)),
      };

  @override
  Widget build(BuildContext context) {
    // A tab that is hidden does no work: no queries, no timers, no rebuilds.
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox.shrink();
    final c = context.c;
    final today = startOfDay(ref.watch(currentMinuteProvider));
    final anchor = _anchor ?? today;
    final report = ref.watch(periodReportProvider((_period, anchor))).valueOrNull;
    final series = ref.watch(netSeriesProvider(anchor)).valueOrNull;

    final income = _IncomeCard(report: report);
    final side = Column(
      children: [
        Expanded(flex: 5, child: _ChartCard(series: series, anchor: anchor, today: today)),
        const SizedBox(height: 18),
        Expanded(flex: 4, child: _SplitCard(report: report)),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PageTitle('Report'),
              const SizedBox(width: 20),
              SegmentedButton<ReportPeriod>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ReportPeriod.daily, label: Text('Daily')),
                  ButtonSegment(value: ReportPeriod.weekly, label: Text('Weekly')),
                  ButtonSegment(value: ReportPeriod.monthly, label: Text('Monthly')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() {
                  _period = s.first;
                  _anchor = null;
                }),
              ),
              const Spacer(),
              _ArrowButton(
                icon: Icons.chevron_left,
                onTap: () => setState(() => _anchor = _step(anchor, -1)),
              ),
              SizedBox(
                width: 190,
                child: Center(
                  child: Text(_label(anchor, today), style: condensed(30, color: c.text)),
                ),
              ),
              _ArrowButton(
                icon: Icons.chevron_right,
                onTap: _atNewest(anchor, today) ? null : () => setState(() => _anchor = _step(anchor, 1)),
              ),
              const SizedBox(width: 14),
              OutlinedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute<void>(builder: (_) => const TransactionsPage())),
                child: const Text('Voids and log'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: income),
                      const SizedBox(width: 22),
                      Expanded(flex: 5, child: side),
                    ],
                  );
                }
                return SingleChildScrollView(
                  child: Column(children: [
                    SizedBox(height: 640, child: income),
                    const SizedBox(height: 18),
                    SizedBox(height: 560, child: side),
                  ]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Material(
      color: c.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Icon(icon, color: onTap == null ? c.muted.withValues(alpha: 0.4) : c.text),
        ),
      ),
    );
  }
}

/// "50 + 15 + 50", cut short when there are many.
String _parts(List<int> parts) {
  if (parts.isEmpty) return '';
  if (parts.length > 8) return '${parts.length} entries';
  return parts.join(' + ');
}

class _IncomeCard extends StatelessWidget {
  const _IncomeCard({required this.report});

  final PeriodReport? report;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final r = report;
    final t = r?.totals;

    Widget line(String label, String note, String amount,
        {bool strong = false, Color? amountColor, bool muted = false}) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 26, vertical: strong ? 16 : 13),
        decoration: BoxDecoration(
          color: strong ? (c.isDark ? c.surface.withValues(alpha: 0.7) : c.raised.withValues(alpha: 0.5)) : null,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: label,
                    style: strong
                        ? condensed(26, color: c.text)
                        : TextStyle(
                            fontFamily: 'Barlow',
                            fontSize: 19,
                            color: muted ? c.muted : c.text),
                  ),
                  if (note.isNotEmpty)
                    TextSpan(
                        text: ' · $note',
                        style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
                ]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text(amount,
                style: strong
                    ? condensed(34, color: amountColor ?? c.text)
                    : TextStyle(
                        fontFamily: 'Barlow',
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: amountColor ?? (muted ? c.muted : c.text))),
          ],
        ),
      );
    }

    String count(List<int> p, String one, String many) =>
        p.isEmpty ? 'none' : '${p.length} ${p.length == 1 ? one : many} (${_parts(p)})';

    final net = t?.net ?? 0;
    final loss = net < 0;
    final tone = loss ? c.red : c.green;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Income', style: condensed(34, color: c.text)),
                const SizedBox(width: 12),
                Text('What the period earned',
                    style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
              ],
            ),
          ),
          if (r == null)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    line('Time', count(r.timeParts, 'session', 'sessions'), formatPeso(t!.timeIncome)),
                    line('Game', count(r.gameParts, 'session', 'sessions'), formatPeso(t.gameIncome)),
                    line('Race', count(r.raceParts, 'race', 'races'), formatPeso(t.raceIncome)),
                    line('Billiard total', '', formatPeso(t.billiard), strong: true),
                    line(
                      'Benta',
                      r.bentaParts.isEmpty
                          ? 'none'
                          : r.bentaParts.map((b) => '${b.name} ${b.qty}').join(' · '),
                      formatPeso(t.benta),
                    ),
                    line('Billiard + Benta', '', formatPeso(t.billiardPlusBenta), strong: true),
                    line(
                      'Expenses',
                      r.expenseParts.isEmpty
                          ? 'none'
                          : r.expenseParts.length > 6
                              ? '${r.expenseParts.length} entries'
                              : r.expenseParts.map((e) => '${e.name} ${e.amount}').join(' + '),
                      t.expenses == 0 ? formatPeso(0) : '– ${formatPeso(t.expenses)}',
                      amountColor: t.expenses == 0 ? c.muted : c.red,
                      muted: t.expenses == 0,
                    ),
                    line('Voids', r.voids == 0 ? 'none' : 'refunded', r.voids == 0 ? formatPeso(0) : '– ${formatPeso(r.voids)}',
                        amountColor: r.voids == 0 ? c.muted : c.red, muted: r.voids == 0),
                    if (r.writtenOff > 0)
                      line('Written off / removed', 'never counted as income', formatPeso(r.writtenOff),
                          muted: true),
                  ],
                ),
              ),
            ),
          Container(
            margin: const EdgeInsets.all(18),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: c.isDark ? 0.08 : 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tone.withValues(alpha: 0.7), width: 1.5),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('Total', style: condensed(30, color: c.text)),
                const SizedBox(width: 10),
                Text(loss ? 'Loss' : 'Profit',
                    style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
                const Spacer(),
                Text(formatPeso(net), style: condensed(64, color: tone)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Seven bars: net profit per day, the chosen day in gold.
class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.series, required this.anchor, required this.today});

  final List<int>? series;
  final DateTime anchor;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final values = series;
    final last = DateTime(anchor.year, anchor.month, anchor.day);

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Net, last 7 days', style: condensed(30, color: c.text)),
              const Spacer(),
              Text('ending ${DateFormat('MMM d').format(last)}',
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: values == null
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, box) {
                      final peak = values.fold<int>(1, (m, v) => v.abs() > m ? v.abs() : m);
                      final barArea = box.maxHeight - 28;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < values.length; i++)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                      height: (barArea * values[i].abs() / peak).clamp(3.0, barArea),
                                      decoration: BoxDecoration(
                                        color: values[i] < 0
                                            ? c.red.withValues(alpha: 0.7)
                                            : (i == values.length - 1
                                                ? c.gold
                                                : c.green.withValues(alpha: c.isDark ? 0.55 : 0.6)),
                                        borderRadius:
                                            const BorderRadius.vertical(top: Radius.circular(8)),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '${DateTime(last.year, last.month, last.day - (values.length - 1 - i)).day}',
                                      style: TextStyle(
                                          fontFamily: 'Barlow',
                                          fontSize: 14,
                                          fontWeight: i == values.length - 1 ? FontWeight.w700 : null,
                                          color: i == values.length - 1 ? c.gold : c.muted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Share of income by source.
class _SplitCard extends StatelessWidget {
  const _SplitCard({required this.report});

  final PeriodReport? report;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = report?.totals;
    final total = t?.billiardPlusBenta ?? 0;

    final rows = [
      ('Game', t?.gameIncome ?? 0, c.blue),
      ('Race', t?.raceIncome ?? 0, c.coral),
      ('Time', t?.timeIncome ?? 0, c.gold),
      ('Benta', t?.benta ?? 0, c.green),
    ];

    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Where the money came from', style: condensed(30, color: c.text)),
          const SizedBox(height: 14),
          Expanded(
            child: total <= 0
                ? Center(
                    child: Text('No income yet.',
                        style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)))
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final (label, amount, color) in rows)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(label,
                                    style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.text)),
                                const Spacer(),
                                Text('${(amount * 100 / total).round()}%',
                                    style: TextStyle(
                                        fontFamily: 'Barlow',
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: c.text)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ThinBar(value: amount / total, color: color, height: 8),
                          ],
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
