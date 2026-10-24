import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../providers.dart';
import '../session/session_page.dart';

/// Full-page "Start game": pick the mode, fill in its details, check the summary, Start.
class StartGamePage extends ConsumerStatefulWidget {
  const StartGamePage({super.key, required this.tableId, required this.tableLabel});

  final String tableId;
  final String tableLabel;

  @override
  ConsumerState<StartGamePage> createState() => _StartGamePageState();
}

class _StartGamePageState extends ConsumerState<StartGamePage> {
  var _mode = PlayMode.time;

  /// Id of the chosen rate, or [_customId] for the Custom tile.
  String? _rateId;
  static const _customId = 'custom';

  final _customMinutes = TextEditingController();
  final _customCharge = TextEditingController();
  final _raceTo = TextEditingController(text: '5');
  final _raceTotal = TextEditingController();
  final _tableFee = TextEditingController();
  final _raceMinutes = TextEditingController();
  var _starting = false;

  @override
  void dispose() {
    for (final c in [_customMinutes, _customCharge, _raceTo, _raceTotal, _tableFee, _raceMinutes]) {
      c.dispose();
    }
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text);

  /// The Time block that would be bought: (minutes, price), or null if not chosen yet.
  ({int minutes, int price})? _timeChoice(List<TimeRate> rates) {
    if (_rateId == _customId) {
      final m = _int(_customMinutes);
      final p = _int(_customCharge);
      return m != null && m > 0 && p != null ? (minutes: m, price: p) : null;
    }
    final rate = rates.where((r) => r.id == _rateId).firstOrNull ?? rates.firstOrNull;
    return rate == null ? null : (minutes: rate.minutes, price: rate.price);
  }

  bool get _raceValid {
    final raceTo = _int(_raceTo);
    final total = _int(_raceTotal);
    final fee = _int(_tableFee);
    final minutes = _raceMinutes.text.isEmpty ? 1 : (_int(_raceMinutes) ?? 0);
    return raceTo != null &&
        raceTo > 0 &&
        total != null &&
        fee != null &&
        fee <= total &&
        minutes > 0;
  }

  Future<void> _start(List<TimeRate> rates) async {
    final repo = ref.read(sessionRepositoryProvider);
    final now = ref.read(clockProvider)();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _starting = true);
    try {
      final String id;
      switch (_mode) {
        case PlayMode.time:
          final t = _timeChoice(rates)!;
          id = await repo.startTimeSession(
              tableId: widget.tableId, minutes: t.minutes, price: t.price, now: now);
        case PlayMode.game:
          id = await repo.startGameSession(tableId: widget.tableId, now: now);
        case PlayMode.race:
          id = await repo.startRaceSession(
            tableId: widget.tableId,
            raceTo: _int(_raceTo)!,
            betTotal: _int(_raceTotal)!,
            tableFee: _int(_tableFee)!,
            minutes: _int(_raceMinutes),
            now: now,
          );
      }
      navigator.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => SessionPage(sessionId: id, tableLabel: widget.tableLabel),
      ));
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      setState(() => _starting = false);
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
      setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rates = ref.watch(timeRatesProvider).valueOrNull ?? const <TimeRate>[];
    final now = ref.watch(currentMinuteProvider);
    final alert = ref.watch(alertMinutesProvider);

    // What the summary shows for the chosen mode.
    final String modeLine;
    final DateTime? ends;
    final int bill;
    final bool canStart;
    switch (_mode) {
      case PlayMode.time:
        final t = _timeChoice(rates);
        modeLine = t == null ? 'Time' : 'Time · ${formatRateLabel(t.minutes)}';
        ends = t == null ? null : now.add(Duration(minutes: t.minutes));
        bill = t?.price ?? 0;
        canStart = t != null;
      case PlayMode.game:
        modeLine = 'Game · open time';
        ends = null;
        bill = 0;
        canStart = true;
      case PlayMode.race:
        modeLine = 'Race to ${_int(_raceTo) ?? '-'}';
        final m = _int(_raceMinutes);
        ends = m == null || m <= 0 ? null : now.add(Duration(minutes: m));
        bill = _int(_tableFee) ?? 0;
        canStart = _raceValid;
    }

    final options = AppCard(
      padding: const EdgeInsets.all(26),
      child: switch (_mode) {
        PlayMode.time => _timeOptions(rates),
        PlayMode.game => _gameOptions(),
        PlayMode.race => _raceOptions(),
      },
    );

    final summary = AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Summary', style: condensed(32, color: c.text)),
          const SizedBox(height: 8),
          SummaryRow('Table', widget.tableLabel),
          SummaryRow('Mode', modeLine),
          SummaryRow('Starts', formatClock(now)),
          SummaryRow('Ends', ends == null ? 'Open' : formatClock(ends)),
          if (ends != null) SummaryRow('End alert', '$alert min before'),
          const SizedBox(height: 40),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_mode == PlayMode.time ? 'To pay' : 'Bill starts at',
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 16, color: c.muted)),
              const Spacer(),
              Text(formatPeso(bill), style: condensed(64, color: c.text)),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: canStart && !_starting ? () => _start(rates) : null,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(58)),
            child: Text('Start ${widget.tableLabel}'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Cancel'),
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
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.chevron_left),
                label: const Text('Tables'),
              ),
              const SizedBox(width: 16),
              Text('Start game · ${widget.tableLabel}', style: condensed(44, color: c.text)),
              const Spacer(),
              SegmentedButton<PlayMode>(
                showSelectedIcon: false,
                segments: [
                  for (final m in PlayMode.values) ButtonSegment(value: m, label: Text(m.label)),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                if (box.maxWidth >= 900) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: SingleChildScrollView(child: options)),
                      const SizedBox(width: 24),
                      SizedBox(width: 390, height: box.maxHeight, child: summary),
                    ],
                  );
                }
                return SingleChildScrollView(
                  child: Column(children: [options, const SizedBox(height: 20), summary]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _heading(String title, String note) {
    final c = context.c;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: condensed(32, color: c.text)),
        const SizedBox(width: 14),
        Expanded(
          child: Text(note,
              style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
        ),
      ],
    );
  }

  Widget _timeOptions(List<TimeRate> rates) {
    final selected = _rateId ?? rates.firstOrNull?.id;
    final custom = selected == _customId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('How long?', 'Pick the time bought. The app computes the price and the end time.'),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final tileWidth = (box.maxWidth - 2 * 14) / 3;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final r in rates)
                  _Tile(
                    width: tileWidth,
                    selected: selected == r.id,
                    onTap: () => setState(() => _rateId = r.id),
                    title: formatRateLabel(r.minutes),
                    subtitle: formatPeso(r.price),
                    goldSubtitle: true,
                  ),
                _Tile(
                  width: tileWidth,
                  selected: custom,
                  onTap: () => setState(() => _rateId = _customId),
                  title: 'Custom',
                  subtitle: 'enter minutes',
                ),
              ],
            );
          },
        ),
        if (custom) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _number(_customMinutes, 'Minutes')),
              const SizedBox(width: 14),
              Expanded(child: _number(_customCharge, 'Charge (₱)')),
            ],
          ),
        ],
      ],
    );
  }

  Widget _gameOptions() {
    final c = context.c;
    final games = ref.watch(gameTypesProvider).valueOrNull ?? const <GameType>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Game', 'Open time. Tap each game when it finishes and its price is added to the bill.'),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, box) {
            final tileWidth = (box.maxWidth - 2 * 14) / 3;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final g in games)
                  _Tile(
                    width: tileWidth,
                    selected: false,
                    onTap: null,
                    title: g.name,
                    subtitle: '${formatPeso(g.pricePerGame)} per game',
                    goldSubtitle: true,
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Text('The bill starts at ₱0 and grows with every game. Prices are set in Settings.',
            style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
      ],
    );
  }

  Widget _raceOptions() {
    final c = context.c;
    final total = _int(_raceTotal);
    final fee = _int(_tableFee);
    final String split;
    if (total == null || fee == null) {
      split = 'Type the race total and the table fee to see the split.';
    } else if (fee > total) {
      split = 'The table fee cannot be more than the race total.';
    } else {
      split = 'Bet money ${formatPeso(total - fee)} (not hall income) · Table fee ${formatPeso(fee)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading('Race', 'The table fee is the hall\'s income. Bet money only passes through.'),
        const SizedBox(height: 18),
        _number(_raceTo, 'Race to'),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _number(_raceTotal, 'Race total (₱)')),
            const SizedBox(width: 14),
            Expanded(child: _number(_tableFee, 'Table fee (₱)')),
          ],
        ),
        const SizedBox(height: 10),
        Text(split, style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
        const SizedBox(height: 14),
        _number(_raceMinutes, 'Time limit in minutes (optional)'),
      ],
    );
  }

  Widget _number(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => setState(() {}),
    );
  }
}

/// A big selectable tile: title over a subtitle, gold when selected.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.width,
    required this.selected,
    required this.onTap,
    required this.title,
    required this.subtitle,
    this.goldSubtitle = false,
  });

  final double width;
  final bool selected;
  final VoidCallback? onTap;
  final String title;
  final String subtitle;
  final bool goldSubtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SizedBox(
      width: width,
      height: 112,
      child: Material(
        color: selected ? c.goldTint : c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? c.gold : c.border, width: selected ? 2 : 1),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, style: condensed(42, color: c.text)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontFamily: 'Barlow',
                      fontSize: 16,
                      fontWeight: goldSubtitle ? FontWeight.w700 : FontWeight.w500,
                      color: goldSubtitle ? c.gold : c.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
