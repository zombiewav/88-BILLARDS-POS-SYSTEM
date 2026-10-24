import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets/logo.dart';
import '../../providers.dart';

/// Logo and branch on the left; sync status and the clock on the right.
class TopBar extends ConsumerWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final now = ref.watch(currentMinuteProvider);
    final compact = MediaQuery.sizeOf(context).width < 760;

    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          const Logo8(size: 40),
          const SizedBox(width: 14),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ref.watch(businessNameProvider), style: condensed(26, color: c.text)),
              Text(ref.watch(branchNameProvider),
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 13, color: c.muted)),
            ],
          ),
          const Spacer(),
          if (!compact) ...[
            _SyncPill(text: 'Works offline · ${syncLabel(ref.watch(lastSyncProvider), now)}'),
            const SizedBox(width: 20),
          ],
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatClock(now), style: condensed(28, color: c.text)),
              Text(DateFormat('EEE, MMM d').format(now),
                  style: TextStyle(fontFamily: 'Barlow', fontSize: 12, color: c.muted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SyncPill extends StatelessWidget {
  const _SyncPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: c.green, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.text)),
        ],
      ),
    );
  }
}
