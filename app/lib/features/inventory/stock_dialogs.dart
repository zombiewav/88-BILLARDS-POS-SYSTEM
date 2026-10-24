import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';

Widget _numberField(TextEditingController c, String label, VoidCallback changed,
    {bool autofocus = false}) {
  return TextField(
    controller: c,
    autofocus: autofocus,
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    onChanged: (_) => changed(),
  );
}

Widget _noteField(TextEditingController c) {
  return TextField(
    controller: c,
    decoration: const InputDecoration(
      labelText: 'Note (optional)',
      border: OutlineInputBorder(),
    ),
  );
}

typedef StockInResult = ({int qty, String note});

class StockInDialog extends StatefulWidget {
  const StockInDialog({super.key, required this.product});

  final Product product;

  @override
  State<StockInDialog> createState() => _StockInDialogState();
}

class _StockInDialogState extends State<StockInDialog> {
  final _qty = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _value => int.tryParse(_qty.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Stock in · ${widget.product.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Now ${widget.product.stock} in stock'),
            const SizedBox(height: 12),
            _numberField(_qty, 'Quantity received', () => setState(() {}), autofocus: true),
            const SizedBox(height: 12),
            _noteField(_note),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _value > 0
              ? () => Navigator.pop<StockInResult>(context, (qty: _value, note: _note.text))
              : null,
          child: const Text('Add stock'),
        ),
      ],
    );
  }
}

/// [damaged] true = remove [value] damaged or lost; false = stock is really [value].
typedef AdjustResult = ({bool damaged, int value, String note});

class AdjustDialog extends StatefulWidget {
  const AdjustDialog({super.key, required this.product});

  final Product product;

  @override
  State<AdjustDialog> createState() => _AdjustDialogState();
}

class _AdjustDialogState extends State<AdjustDialog> {
  late final _value = TextEditingController(text: widget.product.stock.toString());
  final _note = TextEditingController();
  var _damaged = false;

  @override
  void dispose() {
    _value.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _number => int.tryParse(_value.text);

  bool get _valid {
    final n = _number;
    if (n == null) return false;
    return _damaged ? n > 0 && n <= widget.product.stock : true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Adjust · ${widget.product.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Count')),
                ButtonSegment(value: true, label: Text('Damaged / lost')),
              ],
              selected: {_damaged},
              onSelectionChanged: (s) => setState(() {
                _damaged = s.first;
                _value.text = _damaged ? '' : widget.product.stock.toString();
              }),
            ),
            const SizedBox(height: 12),
            Text('Now ${widget.product.stock} in stock'),
            const SizedBox(height: 12),
            _numberField(
              _value,
              _damaged ? 'Quantity damaged or lost' : 'Counted stock',
              () => setState(() {}),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            _noteField(_note),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop<AdjustResult>(
                  context, (damaged: _damaged, value: _number!, note: _note.text))
              : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
