import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'audit.dart';
import 'database.dart';

const _failedKey = 'pin_failed';
const _lockedUntilKey = 'pin_locked_until';

/// Wrong tries allowed before the keypad locks.
const maxPinTries = 5;
const pinLockDuration = Duration(minutes: 5);

/// The outcome of typing a PIN.
sealed class PinResult {
  const PinResult();
}

class PinOk extends PinResult {
  const PinOk(this.staff);

  final StaffMember staff;
}

class PinWrong extends PinResult {
  const PinWrong(this.triesLeft);

  final int triesLeft;
}

class PinLocked extends PinResult {
  const PinLocked(this.until);

  final DateTime until;
}

/// People and PINs. The PIN is the login, so it identifies the person and their
/// role; it is stored salted and hashed, never in plain text. Wrong tries are
/// counted for the whole tablet (a wrong PIN identifies nobody).
class StaffRepository {
  StaffRepository(this.db);

  final AppDatabase db;

  Stream<List<StaffMember>> watchAll() {
    return (db.select(db.staffTable)
          ..where((s) => s.deletedAt.isNull())
          ..orderBy([
            (s) => OrderingTerm.asc(s.role),
            (s) => OrderingTerm.asc(s.createdAt),
          ]))
        .watch();
  }

  /// True once an Owner exists; until then the app asks for a first PIN.
  Future<bool> hasOwner() async {
    final owners = await (db.select(db.staffTable)
          ..where((s) =>
              s.role.equalsValue(StaffRole.owner) & s.active.equals(true) & s.deletedAt.isNull())
          ..limit(1))
        .get();
    return owners.isNotEmpty;
  }

  Future<StaffMember> create({
    required String name,
    required StaffRole role,
    required String pin,
    required DateTime now,
  }) {
    if (name.trim().isEmpty) throw ArgumentError('Name is required');
    _checkPinFormat(pin);

    return db.transaction(() async {
      if (await _find(pin) != null) {
        throw StateError('That PIN is already used by someone else');
      }
      final salt = _newSalt();
      final id = newId();
      await db.into(db.staffTable).insert(StaffTableCompanion.insert(
            id: Value(id),
            name: name.trim(),
            role: role,
            pinSalt: salt,
            pinHash: _hash(salt, pin),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await writeAudit(db,
          action: 'staff_created', entity: 'staff:$id', newValue: '${role.name} ${name.trim()}', now: now);
      return (db.select(db.staffTable)..where((s) => s.id.equals(id))).getSingle();
    });
  }

  /// Owner resets somebody's PIN.
  Future<void> resetPin({required String staffId, required String newPin, required DateTime now}) {
    _checkPinFormat(newPin);
    return db.transaction(() async {
      final holder = await _find(newPin);
      if (holder != null && holder.id != staffId) {
        throw StateError('That PIN is already used by someone else');
      }
      final salt = _newSalt();
      await (db.update(db.staffTable)..where((s) => s.id.equals(staffId))).write(
        StaffTableCompanion(
          pinSalt: Value(salt),
          pinHash: Value(_hash(salt, newPin)),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await writeAudit(db, action: 'pin_reset', entity: 'staff:$staffId', now: now);
    });
  }

  /// Removes a person (kept in the database). The last Owner cannot be removed.
  Future<void> remove({required String staffId, required DateTime now}) {
    return db.transaction(() async {
      final member =
          await (db.select(db.staffTable)..where((s) => s.id.equals(staffId))).getSingle();
      if (member.role == StaffRole.owner) {
        final owners = await (db.select(db.staffTable)
              ..where((s) =>
                  s.role.equalsValue(StaffRole.owner) &
                  s.active.equals(true) &
                  s.deletedAt.isNull()))
            .get();
        if (owners.length <= 1) throw StateError('There must be at least one Owner');
      }
      await (db.update(db.staffTable)..where((s) => s.id.equals(staffId))).write(
        StaffTableCompanion(
          active: const Value(false),
          deletedAt: Value(now),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await writeAudit(db, action: 'staff_removed', entity: 'staff:$staffId', now: now);
    });
  }

  /// Checks a PIN for logging in. Locks the keypad after [maxPinTries] wrong tries.
  Future<PinResult> login(String pin, {required DateTime now}) => _check(pin, now, ownerOnly: false);

  /// Checks that [pin] belongs to an Owner, for approvals (voids, settings).
  Future<PinResult> approveAsOwner(String pin, {required DateTime now}) =>
      _check(pin, now, ownerOnly: true);

  /// When the keypad unlocks, or null if it is not locked.
  Future<DateTime?> lockedUntil(DateTime now) async {
    final raw = await _setting(_lockedUntilKey);
    final until = raw == null ? null : DateTime.tryParse(raw);
    return until != null && until.isAfter(now) ? until : null;
  }

  Future<PinResult> _check(String pin, DateTime now, {required bool ownerOnly}) {
    return db.transaction(() async {
      final locked = await lockedUntil(now);
      if (locked != null) return PinLocked(locked);

      final match = pin.length == pinDigits ? await _find(pin) : null;
      if (match != null && (!ownerOnly || match.role == StaffRole.owner)) {
        await _putSetting(_failedKey, '0');
        return PinOk(match);
      }

      final failed = (int.tryParse(await _setting(_failedKey) ?? '') ?? 0) + 1;
      await writeAudit(db,
          action: 'pin_failed', entity: ownerOnly ? 'owner_approval' : 'login', now: now);
      if (failed >= maxPinTries) {
        final until = now.add(pinLockDuration);
        await _putSetting(_failedKey, '0');
        await _putSetting(_lockedUntilKey, until.toIso8601String());
        return PinLocked(until);
      }
      await _putSetting(_failedKey, '$failed');
      return PinWrong(maxPinTries - failed);
    });
  }

  /// The active person whose PIN is [pin], if any.
  Future<StaffMember?> _find(String pin) async {
    final people = await (db.select(db.staffTable)
          ..where((s) => s.active.equals(true) & s.deletedAt.isNull()))
        .get();
    for (final s in people) {
      if (_hash(s.pinSalt, pin) == s.pinHash) return s;
    }
    return null;
  }

  Future<String?> _setting(String key) async {
    final row = await (db.select(db.appSettings)..where((s) => s.settingKey.equals(key)))
        .getSingleOrNull();
    return row?.settingValue;
  }

  Future<void> _putSetting(String key, String value) {
    return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(settingKey: key, settingValue: value));
  }

  void _checkPinFormat(String pin) {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) throw ArgumentError('A PIN is exactly 6 digits');
  }

  String _newSalt() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  String _hash(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();
}

const pinDigits = 6;
