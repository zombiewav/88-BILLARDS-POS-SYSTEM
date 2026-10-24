import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_colors.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';

/// A settings card: big title, optional "+ Add" button, then the rows.
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.title,
    required this.children,
    this.note,
    this.action,
    this.onAction,
  });

  final String title;
  final String? note;
  final String? action;
  final VoidCallback? onAction;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(title, style: condensed(30, color: c.text)),
              const Spacer(),
              if (action != null)
                OutlinedButton(
                  onPressed: onAction,
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 42)),
                  child: Text(action!),
                ),
            ],
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(note!, style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
          ],
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// One row: a label on the left, anything on the right, a thin line below.
class SettingsRow extends StatelessWidget {
  const SettingsRow({super.key, required this.label, required this.trailing, this.sub, this.last = false});

  final String label;
  final String? sub;
  final Widget trailing;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label, style: TextStyle(fontFamily: 'Barlow', fontSize: 17, color: c.text)),
                if (sub != null)
                  Text(sub!, style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

/// A small number box that saves when you press Enter or tap away.
class SaveField extends StatefulWidget {
  const SaveField({
    super.key,
    required this.value,
    required this.onSave,
    this.prefix,
    this.suffix,
    this.width = 120,
    this.numeric = true,
    this.label,
  });

  final String value;
  final ValueChanged<String> onSave;
  final String? prefix;
  final String? suffix;
  final double width;
  final bool numeric;
  final String? label;

  @override
  State<SaveField> createState() => _SaveFieldState();
}

class _SaveFieldState extends State<SaveField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(SaveField old) {
    super.didUpdateWidget(old);
    // Show a value that changed elsewhere, unless the user is typing here.
    if (!_focus.hasFocus && widget.value != _controller.text) _controller.text = widget.value;
  }

  void _commit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && text != widget.value) widget.onSave(text);
    if (text.isEmpty) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        keyboardType: widget.numeric ? TextInputType.number : TextInputType.text,
        inputFormatters: widget.numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
        textCapitalization: widget.numeric ? TextCapitalization.none : TextCapitalization.words,
        onSubmitted: (_) => _commit(),
        decoration: InputDecoration(
          labelText: widget.label,
          prefixText: widget.prefix == null ? null : '${widget.prefix} ',
          suffixText: widget.suffix == null ? null : ' ${widget.suffix}',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      ),
    );
  }
}

/// One text box in [showFieldsDialog].
class DialogField {
  const DialogField(this.label, {this.numeric = false, this.secret = false, this.maxLength, this.initial = ''});

  final String label;
  final bool numeric;
  final bool secret;
  final int? maxLength;
  final String initial;
}

/// Asks for a few short values. Returns them in order, or null if cancelled.
/// [validate] can return a message to keep the dialog open.
Future<List<String>?> showFieldsDialog(
  BuildContext context, {
  required String title,
  required List<DialogField> fields,
  required String action,
  String? message,
  String? Function(List<String> values)? validate,
}) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _FieldsDialog(
      title: title,
      fields: fields,
      action: action,
      message: message,
      validate: validate,
    ),
  );
}

class _FieldsDialog extends StatefulWidget {
  const _FieldsDialog({
    required this.title,
    required this.fields,
    required this.action,
    this.message,
    this.validate,
  });

  final String title;
  final List<DialogField> fields;
  final String action;
  final String? message;
  final String? Function(List<String>)? validate;

  @override
  State<_FieldsDialog> createState() => _FieldsDialogState();
}

class _FieldsDialogState extends State<_FieldsDialog> {
  late final _controllers = [for (final f in widget.fields) TextEditingController(text: f.initial)];
  String? _error;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _filled => _controllers.every((c) => c.text.trim().isNotEmpty);

  void _submit() {
    final values = [for (final c in _controllers) c.text.trim()];
    final problem = widget.validate?.call(values);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, values);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!, style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
              const SizedBox(height: 14),
            ],
            for (final (i, f) in widget.fields.indexed) ...[
              TextField(
                controller: _controllers[i],
                autofocus: i == 0,
                obscureText: f.secret,
                maxLength: f.maxLength,
                keyboardType: f.numeric ? TextInputType.number : TextInputType.text,
                inputFormatters: f.numeric ? [FilteringTextInputFormatter.digitsOnly] : null,
                textCapitalization: f.numeric ? TextCapitalization.none : TextCapitalization.words,
                decoration: InputDecoration(labelText: f.label, counterText: ''),
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => _filled ? _submit() : null,
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null)
              Text(_error!, style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.red)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _filled ? _submit : null,
          style: FilledButton.styleFrom(minimumSize: const Size(110, 48)),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
