import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/session_repository.dart';
import '../../domain/enums.dart';
import '../../domain/table_status.dart';
import 'table_card.dart';

/// Deep green felt, the same on both themes (the design keeps it dark).
const _felt = Color(0xFF1B4638);
const _feltText = Color(0xFFF2F7F4);

/// The floor plan: tables where they really stand. Tap one for a quick card.
/// In edit mode the Owner drags tables to new places (they snap to the grid) and
/// picks one to resize, rotate or delete from the side panel.
class TablesMap extends ConsumerStatefulWidget {
  const TablesMap({
    super.key,
    required this.rows,
    required this.zones,
    required this.now,
    required this.alertMinutes,
    required this.editing,
    required this.selectedId,
    required this.onSelect,
    required this.onOpen,
    required this.onAddBenta,
    required this.onMove,
    required this.onMoveZone,
  });

  final List<TableWithSession> rows;
  final List<FloorZone> zones;
  final DateTime now;
  final int alertMinutes;
  final bool editing;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final void Function(TableWithSession row) onOpen;
  final void Function(TableWithSession row) onAddBenta;
  final void Function(PoolTable table, int x, int y) onMove;
  final void Function(FloorZone zone, int x, int y) onMoveZone;

  @override
  ConsumerState<TablesMap> createState() => _TablesMapState();
}

class _TablesMapState extends ConsumerState<TablesMap> {
  /// Live drag offsets (pixels) while the Owner moves a table.
  final _drag = <String, Offset>{};

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rows = widget.rows;
    if (rows.isEmpty) return const SizedBox();

    final maxX = [
      ...rows.map((r) => r.table.mapX + r.table.w),
      ...widget.zones.map((z) => z.mapX + z.w),
    ].reduce(math.max);
    final maxY = [
      ...rows.map((r) => r.table.mapY + r.table.h),
      ...widget.zones.map((z) => z.mapY + z.h),
    ].reduce(math.max);

    return Container(
      decoration: BoxDecoration(
        color: c.isDark ? c.card : c.raised.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.isDark ? c.border : const Color(0xFFB9CDC2), width: 1.5),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          const pad = 24.0;
          final w = box.maxWidth - pad * 2;
          final h = box.maxHeight - pad * 2 - 14;
          final unit = math.max(40.0, math.min(w / (maxX + 0.3), h / (maxY + 0.3)));
          final left0 = pad + (w - unit * maxX) / 2;
          const top0 = pad + 14;

          Rect rectAt(int x, int y, int w, int h) => Rect.fromLTWH(
                left0 + x * unit + 6,
                top0 + y * unit + 6,
                w * unit - 12,
                h * unit - 12,
              );
          Rect rectOf(PoolTable t) => rectAt(t.mapX, t.mapY, t.w, t.h);

          final selected = rows.where((r) => r.table.id == widget.selectedId).firstOrNull;

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSelect(null),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 18,
                  top: 14,
                  child: Text('BACK WALL',
                      style: TextStyle(
                          fontFamily: 'Barlow', fontSize: 12, letterSpacing: 1.2, color: c.muted)),
                ),
                for (final z in widget.zones)
                  _positionedZone(z, rectAt(z.mapX, z.mapY, z.w, z.h), widget.selectedId == z.id),
                for (final r in rows) _positioned(r, rectOf(r.table), selected?.table.id == r.table.id),
                if (selected != null && !widget.editing)
                  _popover(selected, rectOf(selected.table), box.biggest),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _positioned(TableWithSession row, Rect base, bool isSelected) {
    final drag = _drag[row.table.id] ?? Offset.zero;
    final rect = base.shift(drag);
    final status = statusOfRow(row, widget.now, widget.alertMinutes);
    final id = row.table.id;

    return Positioned.fromRect(
      rect: rect,
      child: GestureDetector(
        onTap: () => widget.onSelect(isSelected ? null : id),
        onPanStart: widget.editing ? (_) => widget.onSelect(id) : null,
        onPanUpdate: widget.editing
            ? (d) => setState(() => _drag[id] = (_drag[id] ?? Offset.zero) + d.delta)
            : null,
        onPanEnd: widget.editing ? (_) => _drop(row, base) : null,
        child: _Tile(
          row: row,
          status: status,
          now: widget.now,
          selected: isSelected,
          editing: widget.editing,
        ),
      ),
    );
  }

  Widget _positionedZone(FloorZone zone, Rect base, bool isSelected) {
    final drag = _drag[zone.id] ?? Offset.zero;
    final id = zone.id;

    // Outside edit mode a zone is just scenery: taps fall through to the map.
    if (!widget.editing) {
      return Positioned.fromRect(rect: base, child: IgnorePointer(child: _Zone(label: zone.label)));
    }
    return Positioned.fromRect(
      rect: base.shift(drag),
      child: GestureDetector(
        onTap: () => widget.onSelect(isSelected ? null : id),
        onPanStart: (_) => widget.onSelect(id),
        onPanUpdate: (d) => setState(() => _drag[id] = (_drag[id] ?? Offset.zero) + d.delta),
        onPanEnd: (_) {
          final moved = _drag.remove(id) ?? Offset.zero;
          final unit = (base.width + 12) / zone.w;
          final x = math.max(0, zone.mapX + (moved.dx / unit).round());
          final y = math.max(0, zone.mapY + (moved.dy / unit).round());
          setState(() {});
          widget.onMoveZone(zone, x, y);
        },
        child: _Zone(label: zone.label, editing: true, selected: isSelected, size: '${zone.w} × ${zone.h}'),
      ),
    );
  }

  void _drop(TableWithSession row, Rect base) {
    final drag = _drag.remove(row.table.id) ?? Offset.zero;
    // Pixels back to grid units, snapped to whole units.
    final unit = (base.width + 12) / row.table.w;
    final x = math.max(0, row.table.mapX + (drag.dx / unit).round());
    final y = math.max(0, row.table.mapY + (drag.dy / unit).round());
    setState(() {});
    widget.onMove(row.table, x, y);
  }

  Widget _popover(TableWithSession row, Rect tile, Size canvas) {
    final c = context.c;
    const width = 350.0;
    final session = row.session;
    final status = statusOfRow(row, widget.now, widget.alertMinutes);
    final left = tile.left.clamp(8.0, math.max(8.0, canvas.width - width - 8)).toDouble();
    final top = (tile.bottom + 10).clamp(8.0, math.max(8.0, canvas.height - 190)).toDouble();

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: GestureDetector(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.gold, width: 1.5),
            boxShadow: const [
              BoxShadow(color: Color(0x55000000), blurRadius: 24, offset: Offset(0, 8)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(row.table.label, style: condensed(32, color: c.text)),
                  const SizedBox(width: 10),
                  Text(status.label,
                      style: TextStyle(
                          fontFamily: 'Barlow',
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: status.colorIn(c))),
                  const Spacer(),
                  if (session != null)
                    Text(formatPeso(session.total), style: condensed(32, color: c.text)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                session == null
                    ? 'Table is available'
                    : '${modeSummary(ref, session)} · started ${formatClock(session.startedAt)}',
                style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  if (session != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => widget.onAddBenta(row),
                        child: const Text('Add benta'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: () => widget.onOpen(row),
                      child: Text(session == null ? 'Start game' : 'Open table'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The counter, entrance and the like: a quiet outlined box, gold when picked.
class _Zone extends StatelessWidget {
  const _Zone({required this.label, this.editing = false, this.selected = false, this.size});

  final String label;
  final bool editing;
  final bool selected;
  final String? size;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final border = selected ? c.gold : (editing ? c.gold.withValues(alpha: 0.55) : c.border);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: selected ? 2.5 : 1.2),
        color: c.isDark ? c.bg.withValues(alpha: 0.5) : Colors.transparent,
        boxShadow: selected ? [BoxShadow(color: c.gold.withValues(alpha: 0.3), blurRadius: 12)] : null,
      ),
      padding: const EdgeInsets.all(6),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontFamily: 'Barlow', fontSize: 15, color: c.muted)),
            if (editing && size != null)
              Text(size!, style: TextStyle(fontFamily: 'Barlow', fontSize: 12, color: c.muted)),
          ],
        ),
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({
    required this.row,
    required this.status,
    required this.now,
    required this.selected,
    required this.editing,
  });

  final TableWithSession row;
  final TableStatus status;
  final DateTime now;
  final bool selected;
  final bool editing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final session = row.session;
    final end = session?.endsAt;

    final String line;
    final String? clock;
    if (session == null) {
      line = 'Free';
      clock = null;
    } else if (status == TableStatus.waitingToPay) {
      line = 'Waiting to pay';
      clock = null;
    } else {
      line = modeSummary(ref, session);
      clock = end != null
          ? formatCountdown(remainingTime(end, now))
          : formatCountdown(now.difference(session.startedAt));
    }

    // Selected in edit mode: bright gold with a glow. Other tiles: thin gold in edit
    // mode, otherwise the colour of their status.
    final border = selected ? c.gold : (editing ? c.gold.withValues(alpha: 0.55) : status.colorIn(c));

    return Container(
      decoration: BoxDecoration(
        color: _felt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: selected ? 3 : 2),
        boxShadow: selected ? [BoxShadow(color: c.gold.withValues(alpha: 0.35), blurRadius: 14)] : null,
      ),
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, box) {
          final narrow = box.maxWidth < 120;
          final short = box.maxHeight < 90;
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(row.table.label, style: condensed(short ? 28 : 36, color: _feltText)),
                  if (editing)
                    Text('${row.table.w} × ${row.table.h}',
                        style: TextStyle(
                            fontFamily: 'Barlow',
                            fontSize: 14,
                            color: _feltText.withValues(alpha: 0.85)))
                  else ...[
                    if (!narrow)
                      Text(line,
                          style: TextStyle(
                              fontFamily: 'Barlow',
                              fontSize: 14,
                              color: _feltText.withValues(alpha: 0.85))),
                    if (clock != null) Text(clock, style: condensed(short ? 22 : 28, color: _feltText)),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
