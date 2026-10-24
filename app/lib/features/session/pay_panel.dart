import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format.dart';

/// Cash entry with live change. Calls [onPay] with the cash received.
class PayPanel extends StatefulWidget {
  const PayPanel({super.key, required this.total, required this.onPay});

  final int total;
  final Future<void> Function(int cashReceived) onPay;

  @override
  State<PayPanel> createState() => _PayPanelState();
}

class _PayPanelState extends State<PayPanel> {
  final _cash = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _cash.dispose();
    super.dispose();
  }

  int get _received => int.tryParse(_cash.text) ?? 0;

  void _set(int value) => setState(() => _cash.text = value.toString());

  Future<void> _pay() async {
    setState(() => _busy = true);
    try {
      await widget.onPay(_received);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final enough = _received >= widget.total;
    final change = enough ? _received - widget.total : 0;
    final quick = <int>{100, 200, 500, 1000}.where((v) => v >= widget.total);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _cash,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Cash received (₱)',
            border: OutlineInputBorder(),
          ),
          style: text.headlineSmall,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(label: const Text('Exact'), onPressed: () => _set(widget.total)),
            for (final v in quick)
              ActionChip(label: Text(formatPeso(v)), onPressed: () => _set(v)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Change', style: text.titleMedium),
            Text(
              enough ? formatPeso(change) : '-',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: enough && !_busy ? _pay : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: Text('Pay ${formatPeso(widget.total)}'),
        ),
      ],
    );
  }
}
