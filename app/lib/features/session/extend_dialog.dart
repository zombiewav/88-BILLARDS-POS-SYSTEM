import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/database.dart';
import '../../providers.dart';

typedef ExtendChoice = ({int minutes, int amount});

/// Pick a rate or type a custom time and charge. Pops an [ExtendChoice].
class ExtendDialog extends ConsumerStatefulWidget {
  const ExtendDialog({super.key});

  @override
  ConsumerState<ExtendDialog> createState() => _ExtendDialogState();
}

class _ExtendDialogState extends ConsumerState<ExtendDialog> {
  final _minutes = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _minutes.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rates = ref.watch(timeRatesProvider).valueOrNull ?? const <TimeRate>[];
    final customMinutes = int.tryParse(_minutes.text) ?? 0;
    final customAmount = int.tryParse(_amount.text);

    return AlertDialog(
      title: const Text('Extend time'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in rates)
                  ActionChip(
                    label: Text('+${formatMinutes(r.minutes)} · ${formatPeso(r.price)}'),
                    onPressed: () =>
                        Navigator.pop<ExtendChoice>(context, (minutes: r.minutes, amount: r.price)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Custom', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _numberField(_minutes, 'Minutes')),
                const SizedBox(width: 12),
                Expanded(child: _numberField(_amount, 'Charge (₱)')),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: customMinutes > 0 && customAmount != null
              ? () => Navigator.pop<ExtendChoice>(
                  context, (minutes: customMinutes, amount: customAmount))
              : null,
          child: const Text('Add custom'),
        ),
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
