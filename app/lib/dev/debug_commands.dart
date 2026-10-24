import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_repository.dart';
import '../providers.dart';

/// Debug-only remote control, so screens can be opened and photographed without
/// clicking: run with `--dart-define=SEED_DEMO=true`, then write a line like
/// `7|tab:2` (a number, a bar, then the command) into `88pos_cmd.txt` in the temp folder.
/// The number just has to change to repeat a command.
///
/// Commands: `theme:light|dark|auto`,
/// `tab:0..5`, `tables:grid|map`, `open:T4`, `start:T3`, `sell:T4`, `pop`.
const debugCommandsEnabled = kDebugMode && bool.fromEnvironment('SEED_DEMO');

/// The latest command line (number, bar, command), for screens that want to react.
final debugCommandProvider = StateProvider<String?>((ref) => null);

/// The command part of a command line, or null.
String? debugCommandOf(String? raw) {
  if (raw == null) return null;
  final i = raw.indexOf('|');
  return i < 0 ? raw : raw.substring(i + 1);
}

/// Watches the command file and handles the commands that need no screen state
/// (theme). Wrap the app in it.
class DebugCommands extends ConsumerStatefulWidget {
  const DebugCommands({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DebugCommands> createState() => _DebugCommandsState();
}

class _DebugCommandsState extends ConsumerState<DebugCommands> {
  Timer? _timer;
  String? _last;
  final _file = File('${Directory.systemTemp.path}${Platform.pathSeparator}88pos_cmd.txt');

  @override
  void initState() {
    super.initState();
    if (!debugCommandsEnabled) return;
    _timer = Timer.periodic(const Duration(milliseconds: 600), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!await _file.exists()) return;
    final raw = (await _file.readAsString()).trim();
    if (raw.isEmpty || raw == _last) return;
    _last = raw;
    await _handle(debugCommandOf(raw)!);
    if (mounted) ref.read(debugCommandProvider.notifier).state = raw;
  }

  Future<void> _handle(String cmd) async {
    final parts = cmd.split(':');
    switch (parts.first) {
      case 'theme':
        await ref.read(settingsRepositoryProvider).set(kThemeMode, parts.length > 1 ? parts[1] : 'auto');
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
