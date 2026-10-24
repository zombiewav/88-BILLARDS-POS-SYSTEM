import 'database.dart';

/// Keys in the small key/value settings store.
const kBusinessName = 'business_name';
const kBranchName = 'branch_name';
const kAlertMinutes = 'alert_minutes';
const kSoundVibration = 'sound_vibration';
const kLowStockWarning = 'low_stock_warning';
const kSyncMinutes = 'sync_minutes';
const kThemeMode = 'theme_mode';
const kLastSync = 'last_sync_at';

/// Branch name, alert minutes, theme and the like. Values are plain strings.
class SettingsRepository {
  SettingsRepository(this.db);

  final AppDatabase db;

  Stream<Map<String, String>> watchAll() {
    return db.select(db.appSettings).watch().map(
          (rows) => {for (final r in rows) r.settingKey: r.settingValue},
        );
  }

  Future<void> set(String key, String value) {
    return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(settingKey: key, settingValue: value));
  }

  Future<void> setAll(Map<String, String> values) {
    return db.transaction(() async {
      for (final e in values.entries) {
        await set(e.key, e.value);
      }
    });
  }
}
