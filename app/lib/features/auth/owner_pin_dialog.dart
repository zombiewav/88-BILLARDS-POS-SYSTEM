import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../data/database.dart';
import '../../domain/enums.dart';
import '../../providers.dart';
import 'pin_entry.dart';

/// True once an Owner has set a PIN. Until then nothing asks for one.
final ownerPinSetProvider = Provider<bool>((ref) =>
    (ref.watch(staffListProvider).valueOrNull ?? const <StaffMember>[])
        .any((s) => s.role == StaffRole.owner && s.active));

/// Approval for sensitive actions (voids, Settings, map layout, write-offs).
/// With no Owner PIN set it approves straight away as "Device"; otherwise it asks
/// for the PIN. Returns the approver's name, or null if cancelled.
Future<String?> askOwnerApproval(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Owner approval',
  String message = 'Enter the Owner 6-digit PIN to approve.',
}) async {
  if (!ref.read(ownerPinSetProvider)) return 'Device';
  final owner = await requireOwnerPin(context, title: title, message: message);
  return owner?.name;
}

/// Asks an Owner to type their PIN. Returns that Owner, or null if cancelled.
/// Used to approve voids and to open Settings from a Cashier login.
Future<StaffMember?> requireOwnerPin(
  BuildContext context, {
  String title = 'Owner approval',
  String message = 'Enter the Owner 6-digit PIN to approve.',
}) {
  return showDialog<StaffMember>(
    context: context,
    builder: (_) => _OwnerPinDialog(title: title, message: message),
  );
}

class _OwnerPinDialog extends ConsumerWidget {
  const _OwnerPinDialog({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(message,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
              const SizedBox(height: 20),
              PinEntry(
                keyHeight: 62,
                verify: (pin) => ref
                    .read(staffRepositoryProvider)
                    .approveAsOwner(pin, now: ref.read(clockProvider)()),
                onSuccess: (owner) => Navigator.pop(context, owner),
              ),
              const SizedBox(height: 8),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            ],
          ),
        ),
      ),
    );
  }
}
