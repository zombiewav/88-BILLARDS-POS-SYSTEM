import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../dev/debug_commands.dart';
import '../../providers.dart';
import '../auth/owner_pin_dialog.dart';
import '../expenses/expenses_page.dart';
import '../inventory/inventory_page.dart';
import '../reports/reports_page.dart';
import '../sell/sell_page.dart';
import '../settings/settings_page.dart';
import '../session/session_page.dart';
import '../tables/start_game_page.dart';
import '../tables/tables_page.dart';
import 'app_rail.dart';
import 'top_bar.dart';

/// Top bar + left rail around the page. Each destination has its own Navigator,
/// so a table, Start game or Sell page opened from it keeps the bar and rail.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _Destination {
  const _Destination(this.label, this.icon, this.page);

  final String label;
  final IconData icon;
  final Widget page;
}

const _destinations = [
  _Destination('Tables', Icons.tv_rounded, TablesPage()),
  _Destination('Sell', Icons.shopping_cart_outlined, SellPage()),
  _Destination('Stock', Icons.inventory_2_outlined, InventoryPage()),
  _Destination('Expenses', Icons.receipt_long_outlined, ExpensesPage()),
  _Destination('Reports', Icons.bar_chart_rounded, ReportsPage()),
  _Destination('Settings', Icons.tune_rounded, SettingsPage()),
];

const _stockIndex = 2;
const _reportsIndex = 4;
const _settingsIndex = 5;

class _AppShellState extends ConsumerState<AppShell> {
  var _index = 0;

  /// Tabs opened so far. The rest are not built until first used.
  final _visited = <int>{0};
  final _keys = [for (final _ in _destinations) GlobalKey<NavigatorState>()];

  Future<void> _select(int i) async {
    if (i == _index) {
      _keys[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    // Settings holds prices and staff: once an Owner PIN is set, it asks for it.
    if (i == _settingsIndex) {
      final who = await askOwnerApproval(
        context,
        ref,
        title: 'Owner only',
        message: 'Settings are for the Owner. Enter the Owner 6-digit PIN.',
      );
      if (who == null || !mounted) return;
    }
    setState(() {
      _index = i;
      _visited.add(i);
    });
  }

  /// Debug-only: open screens from the command file (see debug_commands.dart).
  void _debugCommand(String? raw) {
    final cmd = debugCommandOf(raw);
    if (cmd == null) return;
    final parts = cmd.split(':');
    final nav = _keys[0].currentState;
    final rows = ref.read(tablesProvider).valueOrNull ?? const [];
    final row = parts.length > 1 ? rows.where((r) => r.table.label == parts[1]).firstOrNull : null;

    switch (parts.first) {
      case 'tab':
        setState(() {
          _index = int.parse(parts[1]);
          _visited.add(_index);
        });
      case 'pop':
        for (final k in _keys) {
          k.currentState?.popUntil((r) => r.isFirst);
        }
      case 'open' when row?.session != null:
        setState(() => _index = 0);
        nav?.popUntil((r) => r.isFirst);
        nav?.push(MaterialPageRoute<void>(
            builder: (_) => SessionPage(sessionId: row!.session!.id, tableLabel: row.table.label)));
      case 'start' when row != null:
        setState(() => _index = 0);
        nav?.popUntil((r) => r.isFirst);
        nav?.push(MaterialPageRoute<void>(
            builder: (_) => StartGamePage(tableId: row.table.id, tableLabel: row.table.label)));
      case 'sell' when row?.session != null:
        setState(() => _index = 0);
        nav?.popUntil((r) => r.isFirst);
        nav?.push(MaterialPageRoute<void>(
            builder: (_) => SellPage(
                attachTo: (sessionId: row!.session!.id, tableLabel: row.table.label))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (debugCommandsEnabled) ref.listen(debugCommandProvider, (_, v) => _debugCommand(v));
    final lowStock = ref.watch(lowStockWarningProvider) ? ref.watch(lowStockCountProvider) : 0;
    final unpaid = ref.watch(unpaidProvider).valueOrNull?.length ?? 0;
    final badges = {_stockIndex: lowStock, _reportsIndex: unpaid};

    return Scaffold(
      body: Column(
        children: [
          const TopBar(),
          Expanded(
            child: Row(
              children: [
                AppRail(
                  items: [
                    for (final (i, d) in _destinations.indexed)
                      RailItem(d.label, d.icon, badge: badges[i] ?? 0),
                  ],
                  selected: _index,
                  onSelect: _select,
                  bottom: _settingsIndex,
                ),
                // Opened tabs stay alive (a half-built cart survives a tab switch) but the
                // hidden ones are paused: Visibility turns their tickers off and the pages skip work.
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      for (final (i, d) in _destinations.indexed)
                        if (_visited.contains(i))
                          Visibility(
                            visible: i == _index,
                            maintainState: true,
                            child: Navigator(
                              key: _keys[i],
                              onGenerateRoute: (_) =>
                                  MaterialPageRoute<void>(builder: (_) => d.page),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
