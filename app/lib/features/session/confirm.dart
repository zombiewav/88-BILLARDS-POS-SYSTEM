import 'package:flutter/material.dart';

/// Asks twice before a money or table action goes through (plan: double confirm).
Future<bool> confirmTwice(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final first = await _ask(context, title, message, 'Continue');
  if (first != true || !context.mounted) return false;
  final second = await _ask(context, 'Are you sure?', 'Tap "$confirmLabel" to confirm.', confirmLabel);
  return second == true;
}

Future<bool?> _ask(BuildContext context, String title, String message, String yes) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
      ],
    ),
  );
}
