import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/theme.dart';
import '../../core/widgets/widgets.dart';

/// What is picked on the map: a table or a zone (counter, entrance...).
class LayoutItem {
  const LayoutItem({
    required this.id,
    required this.label,
    required this.w,
    required this.h,
    required this.isZone,
    this.inUse = false,
  });

  final String id;
  final String label;
  final int w;
  final int h;
  final bool isZone;

  /// A table with a game or an unpaid bill on it cannot be deleted.
  final bool inUse;
}

/// Side panel while editing the floor: add a table, or resize, rotate and delete
/// the selected one. Moving is done by dragging on the map.
class LayoutPanel extends StatelessWidget {
  const LayoutPanel({
    super.key,
    required this.selected,
    required this.onAdd,
    required this.onAddZone,
    required this.onBigger,
    required this.onSmaller,
    required this.onRotate,
    required this.onDelete,
    required this.onDone,
  });

  final LayoutItem? selected;
  final VoidCallback onAdd;
  final VoidCallback onAddZone;
  final VoidCallback onBigger;
  final VoidCallback onSmaller;
  final VoidCallback onRotate;
  final VoidCallback onDelete;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final t = selected;

    Widget tool(
      IconData icon,
      String label,
      VoidCallback? onTap, {
      Color? color,
    }) {
      final off = onTap == null;
      final tone = off ? c.muted.withValues(alpha: 0.5) : color;
      return Expanded(
        child: Material(
          color: c.raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: off
                  ? c.border
                  : (color?.withValues(alpha: 0.7) ?? c.border),
            ),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onTap: onTap,
            child: SizedBox(
              height: 78,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: tone ?? c.text, size: 26),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Barlow',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: tone ?? c.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Edit layout', style: condensed(32, color: c.text)),
                  const SizedBox(height: 4),
                  Text(
                    'Drag a table to move it. Tap one to change it.',
                    style: TextStyle(
                      fontFamily: 'Barlow',
                      fontSize: 14,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onAdd,
                          icon: const Icon(Icons.add),
                          label: const Text('Table'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onAddZone,
                          icon: const Icon(Icons.add),
                          label: const Text('Zone'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'A zone is the counter, entrance, kitchen or anything that is not a table.',
                    style: TextStyle(
                      fontFamily: 'Barlow',
                      fontSize: 12,
                      color: c.muted,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(height: 1, color: c.border),
                  const SizedBox(height: 18),
                  if (t == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text(
                        'Tap a table or zone on the map to make it bigger or smaller, turn it, or delete it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 15,
                          color: c.muted,
                        ),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  t.label,
                                  style: condensed(44, color: c.gold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '${t.w} × ${t.h}',
                              style: TextStyle(
                                fontFamily: 'Barlow',
                                fontSize: 16,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                        if (t.inUse) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${t.label} is in use, so it cannot be deleted. Pay or end its table first.',
                            style: TextStyle(
                              fontFamily: 'Barlow',
                              fontSize: 14,
                              color: c.coral,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            tool(Icons.zoom_out_map, 'Bigger', onBigger),
                            const SizedBox(width: 12),
                            tool(Icons.zoom_in_map, 'Smaller', onSmaller),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            tool(
                              Icons.rotate_90_degrees_cw_outlined,
                              'Turn',
                              onRotate,
                            ),
                            const SizedBox(width: 12),
                            tool(
                              Icons.delete_outline,
                              'Delete',
                              t.inUse ? null : onDelete,
                              color: c.red,
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
