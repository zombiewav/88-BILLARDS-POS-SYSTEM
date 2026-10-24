import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../data/session_repository.dart';
import '../../dev/debug_commands.dart';
import '../../domain/enums.dart';
import '../../providers.dart';
import '../auth/owner_pin_dialog.dart';
import '../sell/sell_page.dart';
import '../session/session_page.dart';
import '../settings/settings_widgets.dart' show DialogField, showFieldsDialog;
import 'layout_panel.dart';
import 'start_game_page.dart';
import 'table_card.dart';
import 'tables_map.dart';

enum _Filter { all, playing, free, ending }

enum _View { grid, map }

class TablesPage extends ConsumerStatefulWidget {
  const TablesPage({super.key});

  @override
  ConsumerState<TablesPage> createState() => _TablesPageState();
}

class _TablesPageState extends ConsumerState<TablesPage> {
  var _filter = _Filter.all;
  var _view = _View.grid;
  var _editing = false;

  /// The table picked on the map (quick card, or the one being edited).
  String? _mapSelected;

  @override
  Widget build(BuildContext context) {
    // A tab that is hidden does no work: no queries, no timers, no rebuilds.
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox.shrink();
    if (debugCommandsEnabled) {
      ref.listen(debugCommandProvider, (_, v) {
        switch (debugCommandOf(v)) {
          case 'tables:map':
            setState(() => _view = _View.map);
          case 'tables:grid':
            setState(() => _view = _View.grid);
          case final String s when s.startsWith('tables:edit'):
            final label = s.split(':').length > 2 ? s.split(':')[2] : 'T3';
            final rows = ref.read(tablesProvider).valueOrNull ?? const <TableWithSession>[];
            setState(() {
              _view = _View.map;
              _editing = true;
              _mapSelected = rows.where((r) => r.table.label == label).firstOrNull?.table.id;
            });
        }
      });
    }
    final c = context.c;
    final rows = ref.watch(tablesProvider).valueOrNull ?? const <TableWithSession>[];
    final now = ref.watch(currentTimeProvider);
    final alert = ref.watch(alertMinutesProvider);

    final statuses = {for (final r in rows) r.table.id: statusOfRow(r, now, alert)};
    int count(bool Function(TableStatus s) test) => statuses.values.where(test).length;
    final playing = count((s) => s != TableStatus.free);
    final free = count((s) => s == TableStatus.free);
    final ending = count((s) => s == TableStatus.endingSoon);

    final shown = rows.where((r) {
      final s = statuses[r.table.id]!;
      return switch (_filter) {
        _Filter.all => true,
        _Filter.playing => s != TableStatus.free,
        _Filter.free => s == TableStatus.free,
        _Filter.ending => s == TableStatus.endingSoon,
      };
    }).toList();

    final isMap = _view == _View.map;
    final zones = ref.watch(floorZonesProvider).valueOrNull ?? const <FloorZone>[];

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PageTitle(isMap ? 'Tables · Map' : 'Tables'),
              const SizedBox(width: 22),
              if (!isMap)
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      PillChip(
                        label: 'All ${rows.length}',
                        selected: _filter == _Filter.all,
                        onTap: () => setState(() => _filter = _Filter.all),
                      ),
                      PillChip(
                        label: 'Playing $playing',
                        selected: _filter == _Filter.playing,
                        onTap: () => setState(() => _filter = _Filter.playing),
                      ),
                      PillChip(
                        label: 'Free $free',
                        selected: _filter == _Filter.free,
                        onTap: () => setState(() => _filter = _Filter.free),
                      ),
                      PillChip(
                        label: 'Ending soon $ending',
                        selected: _filter == _Filter.ending,
                        tone: c.coral,
                        onTap: () => setState(() => _filter = _Filter.ending),
                      ),
                    ],
                  ),
                )
              else
                const Spacer(),
              if (isMap) ...[
                OutlinedButton.icon(
                  onPressed: _toggleEdit,
                  icon: Icon(_editing ? Icons.check : Icons.edit_outlined, size: 20),
                  label: Text(_editing ? 'Done' : 'Edit layout (Owner)'),
                ),
                const SizedBox(width: 12),
              ],
              _ViewToggle(view: _view, onChanged: (v) => setState(() {
                    _view = v;
                    _editing = false;
                  })),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: isMap
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: TablesMap(
                          rows: rows,
                          zones: zones,
                          now: now,
                          alertMinutes: alert,
                          editing: _editing,
                          selectedId: _mapSelected,
                          onSelect: (id) => setState(() => _mapSelected = id),
                          onOpen: _open,
                          onAddBenta: _addBenta,
                          onMove: (table, x, y) => ref.read(tableRepositoryProvider).moveTable(
                              id: table.id, x: x, y: y, now: ref.read(clockProvider)()),
                          onMoveZone: (zone, x, y) => ref.read(tableRepositoryProvider).moveZone(
                              id: zone.id, x: x, y: y, now: ref.read(clockProvider)()),
                        ),
                      ),
                      if (_editing) ...[
                        const SizedBox(width: 20),
                        SizedBox(
                          width: 300,
                          child: LayoutPanel(
                            selected: _picked(rows, zones),
                            onAdd: _addTable,
                            onAddZone: _addZone,
                            onBigger: () => _resize(rows, zones, grow: true),
                            onSmaller: () => _resize(rows, zones, grow: false),
                            onRotate: () => _rotate(rows, zones),
                            onDelete: () => _deleteItem(rows, zones),
                            onDone: () => setState(() {
                              _editing = false;
                              _mapSelected = null;
                            }),
                          ),
                        ),
                      ],
                    ],
                  )
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 340,
                      mainAxisExtent: 300,
                      crossAxisSpacing: 20,
                      mainAxisSpacing: 20,
                    ),
                    itemCount: shown.length,
                    itemBuilder: (context, i) => TableCard(
                      row: shown[i],
                      now: now,
                      alertMinutes: alert,
                      onTap: () => _open(shown[i]),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          _Footer(isMap: isMap, alertMinutes: alert),
        ],
      ),
    );
  }

  Future<void> _toggleEdit() async {
    if (_editing) {
      setState(() {
        _editing = false;
        _mapSelected = null;
      });
      return;
    }
    final who = await askOwnerApproval(
      context,
      ref,
      title: 'Owner only',
      message: 'Only the Owner can change the table layout.',
    );
    if (who == null || !mounted) return;
    setState(() {
      _editing = true;
      _mapSelected = null;
    });
  }

  /// The table or zone picked on the map, if any.
  LayoutItem? _picked(List<TableWithSession> rows, List<FloorZone> zones) {
    final row = rows.where((r) => r.table.id == _mapSelected).firstOrNull;
    final t = row?.table;
    if (t != null) {
      return LayoutItem(
          id: t.id, label: t.label, w: t.w, h: t.h, isZone: false, inUse: row!.session != null);
    }
    final z = zones.where((z) => z.id == _mapSelected).firstOrNull;
    if (z != null) return LayoutItem(id: z.id, label: z.label, w: z.w, h: z.h, isZone: true);
    return null;
  }

  Future<void> _setSize(LayoutItem item, int w, int h) {
    final repo = ref.read(tableRepositoryProvider);
    final now = ref.read(clockProvider)();
    return item.isZone
        ? repo.resizeZone(id: item.id, w: w, h: h, now: now)
        : repo.resizeTable(id: item.id, w: w, h: h, now: now);
  }

  /// Makes the picked item one step longer or shorter along its long side.
  Future<void> _resize(List<TableWithSession> rows, List<FloorZone> zones, {required bool grow}) async {
    final t = _picked(rows, zones);
    if (t == null) return;
    final step = grow ? 1 : -1;
    final longWide = t.w >= t.h;
    await _guard(() => _setSize(t, longWide ? t.w + step : t.w, longWide ? t.h : t.h + step));
  }

  Future<void> _rotate(List<TableWithSession> rows, List<FloorZone> zones) async {
    final t = _picked(rows, zones);
    if (t == null) return;
    await _guard(() => _setSize(t, t.h, t.w));
  }

  Future<void> _addZone() async {
    final v = await showFieldsDialog(
      context,
      title: 'Add a zone',
      message: 'The counter, kitchen, toilet, entrance: anything that is not a table.',
      fields: const [DialogField('Name (e.g. Kitchen)')],
      action: 'Add',
    );
    if (v == null || !mounted) return;
    await _guard(() => ref.read(tableRepositoryProvider).addZone(label: v[0], now: ref.read(clockProvider)()));
    if (!mounted) return;
    final zones = await ref.read(floorZonesProvider.future);
    final added = zones.where((z) => z.label == v[0].trim()).lastOrNull;
    if (added != null) setState(() => _mapSelected = added.id);
  }

  Future<void> _addTable() async {
    final v = await showFieldsDialog(
      context,
      title: 'Add a table',
      fields: const [DialogField('Name (e.g. T9)')],
      action: 'Add',
    );
    if (v == null || !mounted) return;
    await _guard(() => ref.read(tableRepositoryProvider).addTable(label: v[0], now: ref.read(clockProvider)()));
    if (!mounted) return;
    // Pick the new table so it can be moved or resized straight away.
    final rows = ref.read(tablesProvider).valueOrNull ?? const <TableWithSession>[];
    final added = rows.where((r) => r.table.label == v[0].trim()).firstOrNull;
    if (added != null) setState(() => _mapSelected = added.table.id);
  }

  Future<void> _deleteItem(List<TableWithSession> rows, List<FloorZone> zones) async {
    final t = _picked(rows, zones);
    if (t == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${t.label}?'),
        content: Text(t.isZone
            ? 'It is taken off the floor map.'
            : 'The table leaves the floor. Its past sales and reports stay.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ctx.c.red, foregroundColor: ctx.c.bg),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = ref.read(tableRepositoryProvider);
    final now = ref.read(clockProvider)();
    await _guard(() => t.isZone ? repo.removeZone(id: t.id, now: now) : repo.removeTable(id: t.id, now: now));
    if (mounted) setState(() => _mapSelected = null);
  }

  Future<void> _guard(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
    }
  }

  void _open(TableWithSession row) {
    final session = row.session;
    final route = session == null
        ? StartGamePage(tableId: row.table.id, tableLabel: row.table.label)
        : SessionPage(sessionId: session.id, tableLabel: row.table.label);
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => route));
  }

  void _addBenta(TableWithSession row) {
    final session = row.session;
    if (session == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SellPage(attachTo: (sessionId: session.id, tableLabel: row.table.label)),
    ));
  }
}

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.view, required this.onChanged});

  final _View view;
  final ValueChanged<_View> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_View>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: _View.grid, label: Text('Grid')),
        ButtonSegment(value: _View.map, label: Text('Map')),
      ],
      selected: {view},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.isMap, required this.alertMinutes});

  final bool isMap;
  final int alertMinutes;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style = TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted);

    Widget key(Color color, String text) => Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 11,
                height: 11,
                decoration: isMap
                    ? BoxDecoration(
                        border: Border.all(color: color, width: 2),
                        borderRadius: BorderRadius.circular(3))
                    : BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(text, style: style),
            ],
          ),
        );

    return Row(
      children: [
        key(c.blue, 'Playing'),
        key(c.green, 'Free'),
        key(c.coral, isMap ? 'Ending soon' : 'Ending soon (alert $alertMinutes min before)'),
        if (isMap) key(c.gold, 'Selected'),
        const Spacer(),
        Flexible(
          child: Text(
            isMap
                ? 'Layout matches the real floor. The owner drags tables to arrange them; '
                    'each branch keeps its own map.'
                : 'Tap a table to see its game, timer and bill',
            style: style,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
