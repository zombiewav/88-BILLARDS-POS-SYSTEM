import 'package:flutter/material.dart';

typedef ReasonResult = ({String reason, bool checked});

/// Asks for a typed reason before a void, write-off or delete.
/// With [checkboxLabel] it also asks one yes/no question (returned as `checked`).
Future<ReasonResult?> showReasonDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? checkboxLabel,
  bool checkboxInitial = false,
}) {
  return showDialog<ReasonResult>(
    context: context,
    builder: (_) => _ReasonDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      checkboxLabel: checkboxLabel,
      checkboxInitial: checkboxInitial,
    ),
  );
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.checkboxLabel,
    required this.checkboxInitial,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String? checkboxLabel;
  final bool checkboxInitial;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  late var _checked = widget.checkboxInitial;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _valid => _reason.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.message),
            const SizedBox(height: 16),
            TextField(
              controller: _reason,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason (required)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (widget.checkboxLabel != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(widget.checkboxLabel!),
                value: _checked,
                onChanged: (v) => setState(() => _checked = v ?? false),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.pop<ReasonResult>(
                  context, (reason: _reason.text.trim(), checked: _checked))
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
