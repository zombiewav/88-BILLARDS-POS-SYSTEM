import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/widgets/widgets.dart';
import '../../data/database.dart';
import '../../data/session_repository.dart';
import '../../data/settings_repository.dart';
import '../../domain/enums.dart';
import '../../providers.dart';
import '../common/reason_dialog.dart';
import 'settings_widgets.dart';

/// Branch, prices, tables, alerts, sync, people and look. The Owner's page.
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A tab that is hidden does no work: no queries, no timers, no rebuilds.
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox.shrink();
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BranchCard(),
        const SizedBox(height: 18),
        const _GamePricesCard(),
        const SizedBox(height: 18),
        const _TimeRatesCard(),
      ],
    );
    // Split so both columns end at about the same height (no empty half when scrolled).
    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _AlertsCard(),
        const SizedBox(height: 18),
        const _SyncCard(),
        const SizedBox(height: 18),
        const _StaffCard(),
        const SizedBox(height: 18),
        const _TablesCard(),
        const SizedBox(height: 18),
        const _AppearanceCard(),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageTitle('Settings'),
          const SizedBox(height: 18),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 28),
                child: box.maxWidth >= 900
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: left),
                          const SizedBox(width: 22),
                          Expanded(child: right),
                        ],
                      )
                    : Column(children: [left, const SizedBox(height: 18), right]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Runs a change and shows its message if it is refused.
Future<void> _guard(BuildContext context, Future<void> Function() action) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
  } on StateError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } on ArgumentError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
  }
}

class _BranchCard extends ConsumerWidget {
  const _BranchCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(settingsRepositoryProvider);
    return SettingsCard(
      title: 'Branch',
      note: 'Shown at the top of every screen and on the server dashboard.',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(
                child: SaveField(
                  label: 'Hall name',
                  numeric: false,
                  width: double.infinity,
                  value: ref.watch(businessNameProvider),
                  onSave: (v) => repo.set(kBusinessName, v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SaveField(
                  label: 'Branch',
                  numeric: false,
                  width: double.infinity,
                  value: ref.watch(branchNameProvider),
                  onSave: (v) => repo.set(kBranchName, v),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GamePricesCard extends ConsumerWidget {
  const _GamePricesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final games = ref.watch(gameTypesProvider).valueOrNull ?? const <GameType>[];
    final repo = ref.read(pricingRepositoryProvider);

    return SettingsCard(
      title: 'Game prices',
      action: '+ Add',
      onAction: () async {
        final v = await showFieldsDialog(
          context,
          title: 'Add a game',
          fields: const [DialogField('Name (e.g. 9 balls)'), DialogField('Price per game (₱)', numeric: true)],
          action: 'Add',
        );
        if (v == null || !context.mounted) return;
        await _guard(context,
            () => repo.addGame(name: v[0], price: int.parse(v[1]), now: ref.read(clockProvider)()));
      },
      children: [
        for (final g in games)
          SettingsRow(
            label: g.name,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SaveField(
                  prefix: '₱',
                  suffix: 'per game',
                  width: 170,
                  value: '${g.pricePerGame}',
                  onSave: (v) => _guard(context,
                      () => repo.setGamePrice(id: g.id, price: int.parse(v), now: ref.read(clockProvider)())),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.delete_outline, color: c.muted),
                  onPressed: () => _guard(context,
                      () => repo.removeGame(id: g.id, now: ref.read(clockProvider)())),
                ),
              ],
            ),
          ),
        SettingsRow(
          label: 'Custom race',
          last: true,
          trailing: Text('table fee entered at start',
              style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.muted)),
        ),
      ],
    );
  }
}

class _TimeRatesCard extends ConsumerWidget {
  const _TimeRatesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final rates = ref.watch(timeRatesProvider).valueOrNull ?? const <TimeRate>[];
    final repo = ref.read(pricingRepositoryProvider);

    return SettingsCard(
      title: 'Time rates',
      action: '+ Add',
      onAction: () async {
        final v = await showFieldsDialog(
          context,
          title: 'Add a time rate',
          fields: const [DialogField('Minutes (e.g. 45)', numeric: true), DialogField('Price (₱)', numeric: true)],
          action: 'Add',
        );
        if (v == null || !context.mounted) return;
        await _guard(
            context,
            () => repo.addTimeRate(
                minutes: int.parse(v[0]), price: int.parse(v[1]), now: ref.read(clockProvider)()));
      },
      children: [
        for (final (i, r) in rates.indexed)
          SettingsRow(
            label: formatMinutes(r.minutes),
            last: i == rates.length - 1,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SaveField(
                  prefix: '₱',
                  width: 130,
                  value: '${r.price}',
                  onSave: (v) => _guard(context,
                      () => repo.setTimeRatePrice(id: r.id, price: int.parse(v), now: ref.read(clockProvider)())),
                ),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.delete_outline, color: c.muted),
                  onPressed: () => _guard(context,
                      () => repo.removeTimeRate(id: r.id, now: ref.read(clockProvider)())),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TablesCard extends ConsumerWidget {
  const _TablesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final rows = ref.watch(tablesProvider).valueOrNull ?? const <TableWithSession>[];
    final repo = ref.read(tableRepositoryProvider);

    return SettingsCard(
      title: 'Tables',
      note: 'Drag them into place with Edit layout on the Tables map.',
      action: '+ Add',
      onAction: () async {
        final v = await showFieldsDialog(
          context,
          title: 'Add a table',
          fields: const [DialogField('Name (e.g. T9)')],
          action: 'Add',
        );
        if (v == null || !context.mounted) return;
        await _guard(context, () => repo.addTable(label: v[0], now: ref.read(clockProvider)()));
      },
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final r in rows)
                Container(
                  padding: const EdgeInsets.only(left: 16, right: 4),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(r.table.label,
                          style: TextStyle(
                              fontFamily: 'Barlow',
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: c.text)),
                      if (r.session != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('in use',
                              style: TextStyle(fontFamily: 'Barlow', fontSize: 12, color: c.coral)),
                        ),
                      IconButton(
                        tooltip: r.session != null ? 'In use' : 'Remove',
                        icon: Icon(Icons.close, size: 18, color: c.muted),
                        onPressed: r.session != null
                            ? null
                            : () => _guard(context,
                                () => repo.removeTable(id: r.table.id, now: ref.read(clockProvider)())),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertsCard extends ConsumerWidget {
  const _AlertsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(settingsRepositoryProvider);

    return SettingsCard(
      title: 'Alerts',
      children: [
        SettingsRow(
          label: 'Alert before a table ends',
          trailing: SaveField(
            suffix: 'min',
            width: 120,
            value: '${ref.watch(alertMinutesProvider)}',
            onSave: (v) => repo.set(kAlertMinutes, '${(int.tryParse(v) ?? 5).clamp(1, 120)}'),
          ),
        ),
        SettingsRow(
          label: 'Sound and vibration',
          trailing: Switch(
            value: ref.watch(soundVibrationProvider),
            onChanged: (v) => repo.set(kSoundVibration, '$v'),
          ),
        ),
        SettingsRow(
          label: 'Low-stock warning in app',
          last: true,
          trailing: Switch(
            value: ref.watch(lowStockWarningProvider),
            onChanged: (v) => repo.set(kLowStockWarning, '$v'),
          ),
        ),
      ],
    );
  }
}

class _SyncCard extends ConsumerWidget {
  const _SyncCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(currentMinuteProvider);
    final last = ref.watch(lastSyncProvider);
    final waiting = ref.watch(unsyncedCountProvider).valueOrNull ?? 0;

    return SettingsCard(
      title: 'Sync',
      children: [
        SettingsRow(
          label: 'Sync with server every',
          trailing: SaveField(
            suffix: 'min',
            width: 120,
            value: '${ref.watch(syncMinutesProvider)}',
            onSave: (v) => ref
                .read(settingsRepositoryProvider)
                .set(kSyncMinutes, '${(int.tryParse(v) ?? 5).clamp(1, 120)}'),
          ),
        ),
        SettingsRow(
          label: last == null ? 'Not synced yet' : 'Last sync ${formatClock(last)}',
          sub: '$waiting ${waiting == 1 ? 'change' : 'changes'} waiting',
          last: true,
          trailing: OutlinedButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'No server is connected yet. ${syncLabel(last, now)}; everything stays saved on this tablet.'),
            )),
            child: const Text('Sync now'),
          ),
        ),
      ],
    );
  }
}

class _StaffCard extends ConsumerWidget {
  const _StaffCard();

  static const _ownerNote = '6-digit PIN · everything, approves voids, edits prices and map';
  static const _cashierNote = '6-digit PIN · tables, sell, expenses. Void needs Owner PIN';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final staff = ref.watch(staffListProvider).valueOrNull ?? const <StaffMember>[];
    final hasOwner = staff.any((s) => s.role == StaffRole.owner && s.active);
    final repo = ref.read(staffRepositoryProvider);

    String? pinProblem(List<String> v, int pinAt) {
      if (!RegExp(r'^\d{6}$').hasMatch(v[pinAt])) return 'A PIN is exactly 6 digits.';
      if (v[pinAt] != v[pinAt + 1]) return 'The two PINs do not match.';
      return null;
    }

    Future<void> add(StaffRole role) async {
      final v = await showFieldsDialog(
        context,
        title: role == StaffRole.owner ? 'Set the Owner PIN' : 'Add a cashier',
        message: role == StaffRole.owner
            ? 'Once set, voids and Settings ask for this PIN.'
            : 'The PIN is their login, so it must be different from everyone else\'s.',
        fields: [
          DialogField('Name', initial: role == StaffRole.owner ? 'Owner' : ''),
          const DialogField('6-digit PIN', numeric: true, secret: true, maxLength: 6),
          const DialogField('Type the PIN again', numeric: true, secret: true, maxLength: 6),
        ],
        action: 'Save',
        validate: (v) => pinProblem(v, 1),
      );
      if (v == null || !context.mounted) return;
      await _guard(context,
          () => repo.create(name: v[0], role: role, pin: v[1], now: ref.read(clockProvider)()));
    }

    Future<void> resetPin(StaffMember s) async {
      final v = await showFieldsDialog(
        context,
        title: 'New PIN for ${s.name}',
        fields: const [
          DialogField('6-digit PIN', numeric: true, secret: true, maxLength: 6),
          DialogField('Type the PIN again', numeric: true, secret: true, maxLength: 6),
        ],
        action: 'Save',
        validate: (v) => pinProblem(v, 0),
      );
      if (v == null || !context.mounted) return;
      await _guard(context,
          () => repo.resetPin(staffId: s.id, newPin: v[0], now: ref.read(clockProvider)()));
    }

    Future<void> remove(StaffMember s) async {
      final r = await showReasonDialog(
        context,
        title: 'Remove ${s.name}?',
        message: 'They can no longer use their PIN. This is recorded in the audit log.',
        confirmLabel: 'Remove',
      );
      if (r == null || !context.mounted) return;
      await _guard(context, () => repo.remove(staffId: s.id, now: ref.read(clockProvider)()));
    }

    return SettingsCard(
      title: 'Staff and roles',
      action: hasOwner ? '+ Add' : 'Set Owner PIN',
      onAction: () => add(hasOwner ? StaffRole.cashier : StaffRole.owner),
      children: [
        if (!hasOwner)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'No Owner PIN yet, so voids and Settings are open to anyone on this tablet. '
              'Set one to protect them.',
              style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.coral),
            ),
          ),
        for (final (i, s) in staff.indexed)
          SettingsRow(
            label: s.name,
            sub: s.role == StaffRole.owner ? _ownerNote : _cashierNote,
            last: i == staff.length - 1,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(onPressed: () => resetPin(s), child: const Text('Reset PIN')),
                IconButton(
                  tooltip: 'Remove',
                  icon: Icon(Icons.delete_outline, color: c.muted),
                  onPressed: () => remove(s),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return SettingsCard(
      title: 'Appearance',
      children: [
        SettingsRow(
          label: 'Theme',
          last: true,
          trailing: SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
            ],
            selected: {mode},
            onSelectionChanged: (s) => ref.read(settingsRepositoryProvider).set(
                  kThemeMode,
                  switch (s.first) {
                    ThemeMode.dark => 'dark',
                    ThemeMode.light => 'light',
                    ThemeMode.system => 'auto',
                  },
                ),
          ),
        ),
      ],
    );
  }
}
