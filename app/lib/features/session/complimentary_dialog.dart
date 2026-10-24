import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/database.dart';
import '../../providers.dart';

typedef ComplimentaryChoice = ({String productId, int qty, String note});

/// Pick a drink and a quantity to give free to a race.
class ComplimentaryDialog extends ConsumerStatefulWidget {
  const ComplimentaryDialog({super.key});

  @override
  ConsumerState<ComplimentaryDialog> createState() => _ComplimentaryDialogState();
}

class _ComplimentaryDialogState extends ConsumerState<ComplimentaryDialog> {
  String? _productId;
  var _qty = 1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = [
      for (final p in ref.watch(productsProvider).valueOrNull ?? const <Product>[])
        if (p.active && p.stock > 0) p,
    ];
    final selected = products.where((p) => p.id == _productId).firstOrNull;
    final maxQty = selected?.stock ?? 1;
    final qty = _qty.clamp(1, maxQty);
    final unit = selected == null ? 0 : (selected.costPrice ?? selected.price);

    return AlertDialog(
      title: const Text('Give a free drink'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: selected?.id,
              decoration: const InputDecoration(
                labelText: 'Drink',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final p in products)
                  DropdownMenuItem(value: p.id, child: Text('${p.name} · ${p.stock} left')),
              ],
              onChanged: (v) => setState(() {
                _productId = v;
                _qty = 1;
              }),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Quantity'),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: qty > 1 ? () => setState(() => _qty = qty - 1) : null,
                ),
                Text('$qty', style: Theme.of(context).textTheme.titleLarge),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: selected != null && qty < maxQty
                      ? () => setState(() => _qty = qty + 1)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              selected == null
                  ? 'Not charged to the customer.'
                  : 'Not charged to the customer. Counts as a ${formatPeso(unit * qty)} expense.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: selected == null
              ? null
              : () => Navigator.pop<ComplimentaryChoice>(
                  context, (productId: selected.id, qty: qty, note: _note.text)),
          child: const Text('Give'),
        ),
      ],
    );
  }
}
