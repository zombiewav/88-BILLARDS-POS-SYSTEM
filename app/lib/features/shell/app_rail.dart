import 'package:flutter/material.dart';

import '../../core/app_colors.dart';

class RailItem {
  const RailItem(this.label, this.icon, {this.badge = 0});

  final String label;
  final IconData icon;

  /// Count shown in a small red badge (low stock, unpaid bills).
  final int badge;
}

/// The left navigation: icon over label, the selected one on a green tile,
/// Settings pinned to the bottom.
class AppRail extends StatelessWidget {
  const AppRail({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.bottom,
  });

  /// Items from the top.
  final List<RailItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  /// Index (into the same list as [onSelect]) of the item pinned to the bottom.
  final int bottom;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: 100,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            if (i != bottom) _Tile(item: items[i], selected: i == selected, onTap: () => onSelect(i)),
          const Spacer(),
          _Tile(item: items[bottom], selected: bottom == selected, onTap: () => onSelect(bottom)),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.selected, required this.onTap});

  final RailItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final color = selected ? c.gold : c.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Material(
        color: selected ? c.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: SizedBox(
            height: 70,
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Badge(
                  isLabelVisible: item.badge > 0,
                  label: Text('${item.badge}'),
                  backgroundColor: c.red,
                  textColor: c.bg,
                  child: Icon(item.icon, color: color, size: 26),
                ),
                const SizedBox(height: 4),
                Text(item.label,
                    style: TextStyle(
                        fontFamily: 'Barlow',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? c.gold : c.text.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
