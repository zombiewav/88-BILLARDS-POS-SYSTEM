import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../providers.dart';

/// What the cashier chose on the Start screen.
sealed class StartChoice {
  const StartChoice();
}

class TimeStart extends StartChoice {
  const TimeStart(this.rate);

  final TimeRate rate;
}

class GameStart extends StartChoice {
  const GameStart();
}

class RaceStart extends StartChoice {
  const RaceStart({
    required this.raceTo,
    required this.betTotal,
    required this.tableFee,
    this.minutes,
  });

  final int raceTo;
  final int betTotal;
  final int tableFee;
  final int? minutes;
}

/// Pick a mode, then its details. Pops a [StartChoice].
class StartSessionDialog extends ConsumerStatefulWidget {
  const StartSessionDialog({super.key, required this.tableLabel});

  final String tableLabel;

  @override
  ConsumerState<StartSessionDialog> createState() => _StartSessionDialogState();
}

class _StartSessionDialogState extends ConsumerState<StartSessionDialog> {
  var _mode = PlayMode.time;
  String? _rateId;

  final _raceTo = TextEditingController(text: '5');
  final _raceTotal = TextEditingController();
  final _tableFee = TextEditingController();
  final _raceMinutes = TextEditingController();

  @override
  void dispose() {
    _raceTo.dispose();
    _raceTotal.dispose();
    _tableFee.dispose();
    _raceMinutes.dispose();
    super.dispose();
  }

  int? _int(TextEditingController c) => int.tryParse(c.text);

  /// The race form is valid when race-to is set, both amounts are typed and the
  /// table fee fits inside the total.
  bool get _raceValid {
    final raceTo = _int(_raceTo);
    final total = _int(_raceTotal);
    final fee = _int(_tableFee);
    return raceTo != null && raceTo > 0 && total != null && fee != null && fee <= total;
  }

  @override
  Widget build(BuildContext context) {
    final rates = ref.watch(timeRatesProvider).valueOrNull ?? const <TimeRate>[];
    final rate = rates.where((r) => r.id == _rateId).firstOrNull ??
        (rates.isEmpty ? null : rates.first);

    return AlertDialog(
      title: Text('Start ${widget.tableLabel}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<PlayMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: PlayMode.time, label: Text('Time')),
                  ButtonSegment(value: PlayMode.game, label: Text('Game')),
                  ButtonSegment(value: PlayMode.race, label: Text('Race')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              const SizedBox(height: 20),
              switch (_mode) {
                PlayMode.time => _timeForm(rates, rate),
                PlayMode.game => _gameForm(),
                PlayMode.race => _raceForm(),
              },
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _startAction(rate), child: const Text('Start')),
      ],
    );
  }

  VoidCallback? _startAction(TimeRate? rate) {
    switch (_mode) {
      case PlayMode.time:
        return rate == null ? null : () => Navigator.pop<StartChoice>(context, TimeStart(rate));
      case PlayMode.game:
        return () => Navigator.pop<StartChoice>(context, const GameStart());
      case PlayMode.race:
        if (!_raceValid) return null;
        return () => Navigator.pop<StartChoice>(
              context,
              RaceStart(
                raceTo: _int(_raceTo)!,
                betTotal: _int(_raceTotal)!,
                tableFee: _int(_tableFee)!,
                minutes: _int(_raceMinutes),
              ),
            );
    }
  }

  Widget _timeForm(List<TimeRate> rates, TimeRate? selected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('How long?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in rates)
              ChoiceChip(
                label: Text('${formatMinutes(r.minutes)} · ${formatPeso(r.price)}'),
                selected: selected?.id == r.id,
                onSelected: (_) => setState(() => _rateId = r.id),
              ),
          ],
        ),
      ],
    );
  }

  Widget _gameForm() {
    return Text(
      'Open time. After each finished game, tap that game on the table '
      'screen and its price is added to what the customer owes.',
      style: Theme.of(context).textTheme.bodyLarge,
    );
  }

  Widget _raceForm() {
    final total = _int(_raceTotal);
    final fee = _int(_tableFee);
    final text = Theme.of(context).textTheme;

    final String split;
    if (total == null || fee == null) {
      split = 'Type the race total and the table fee to see the split.';
    } else if (fee > total) {
      split = 'The table fee cannot be more than the race total.';
    } else {
      split = 'Bet money ${formatPeso(total - fee)} (not hall income) · '
          'Table fee ${formatPeso(fee)}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _numberField(_raceTo, 'Race to'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _numberField(_raceTotal, 'Race total (₱)')),
            const SizedBox(width: 12),
            Expanded(child: _numberField(_tableFee, 'Table fee (₱)')),
          ],
        ),
        const SizedBox(height: 8),
        Text(split, style: text.bodyMedium),
        const SizedBox(height: 12),
        _numberField(_raceMinutes, 'Time limit in minutes (optional)'),
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      onChanged: (_) => setState(() {}),
    );
  }
}
