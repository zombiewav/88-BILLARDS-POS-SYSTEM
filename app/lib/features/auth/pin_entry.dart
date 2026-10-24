import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_colors.dart';
import '../../core/format.dart';
import '../../core/widgets/pin_pad.dart';
import '../../data/database.dart';
import '../../data/staff_repository.dart';
import '../../providers.dart';

/// Dots and keypad that check a 6-digit PIN as soon as it is complete.
/// [verify] decides what the PIN is checked against (login or Owner approval).
class PinEntry extends ConsumerStatefulWidget {
  const PinEntry({
    super.key,
    required this.verify,
    required this.onSuccess,
    this.keyHeight = 74,
  });

  final Future<PinResult> Function(String pin) verify;
  final ValueChanged<StaffMember> onSuccess;
  final double keyHeight;

  @override
  ConsumerState<PinEntry> createState() => _PinEntryState();
}

class _PinEntryState extends ConsumerState<PinEntry> {
  var _pin = '';
  var _error = false;
  var _busy = false;
  String? _message;
  DateTime? _lockedUntil;

  bool get _locked {
    final until = _lockedUntil;
    return until != null && until.isAfter(ref.read(clockProvider)());
  }

  void _digit(int n) {
    if (_busy || _locked || _pin.length >= pinLength) return;
    setState(() {
      _pin += '$n';
      _error = false;
      _message = null;
    });
    if (_pin.length == pinLength) _submit();
  }

  void _backspace() {
    if (_busy || _pin.isEmpty) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = false;
    });
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final result = await widget.verify(_pin);
    if (!mounted) return;

    switch (result) {
      case PinOk(:final staff):
        widget.onSuccess(staff);
        setState(() => _busy = false);
        return;
      case PinWrong(:final triesLeft):
        _message = triesLeft == 1 ? 'Wrong PIN. 1 try left.' : 'Wrong PIN. $triesLeft tries left.';
      case PinLocked(:final until):
        _lockedUntil = until;
        _message = 'Too many tries. Try again at ${formatClock(until)}.';
    }
    setState(() {
      _error = true;
      _busy = false;
    });
    // Let the red dots show for a moment, then clear them.
    unawaited(Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _pin = '');
    }));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PinDots(filled: _pin.length, error: _error),
        SizedBox(
          height: 36,
          child: Center(
            child: _message == null
                ? null
                : Text(_message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'Barlow', fontSize: 14, color: c.red)),
          ),
        ),
        PinPad(onDigit: _digit, onBackspace: _backspace, keyHeight: widget.keyHeight),
      ],
    );
  }
}
