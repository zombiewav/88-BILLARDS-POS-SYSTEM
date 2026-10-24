import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../domain/enums.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// Set once at startup so every new row is stamped with where it was created.
class DeviceContext {
  static String deviceId = 'unknown-device';
  static String branchId = 'main';

  /// Who is logged in on this tablet, stamped on sessions, sales and voids.
  static String? staffName;
}

/// Columns every synced row carries (plan section 9).
mixin BaseColumns on Table {
  TextColumn get id => text().clientDefault(newId)();
  TextColumn get branchId => text().clientDefault(() => DeviceContext.branchId)();
  TextColumn get deviceId => text().clientDefault(() => DeviceContext.deviceId)();
  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PoolTable')
class PoolTables extends Table with BaseColumns {
  TextColumn get label => text()();
  IntColumn get mapX => integer().withDefault(const Constant(0))();
  IntColumn get mapY => integer().withDefault(const Constant(0))();
  IntColumn get w => integer().withDefault(const Constant(1))();
  IntColumn get h => integer().withDefault(const Constant(1))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

/// Things on the floor map that are not tables: the counter, the entrance, a kitchen...
@DataClassName('FloorZone')
class FloorZones extends Table with BaseColumns {
  TextColumn get label => text()();
  IntColumn get mapX => integer().withDefault(const Constant(0))();
  IntColumn get mapY => integer().withDefault(const Constant(0))();
  IntColumn get w => integer().withDefault(const Constant(2))();
  IntColumn get h => integer().withDefault(const Constant(1))();
}

class TimeRates extends Table with BaseColumns {
  IntColumn get minutes => integer()();
  IntColumn get price => integer()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class GameTypes extends Table with BaseColumns {
  TextColumn get name => text()();
  IntColumn get pricePerGame => integer()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class Sessions extends Table with BaseColumns {
  TextColumn get tableId => text().references(PoolTables, #id)();
  TextColumn get mode => textEnum<PlayMode>()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endsAt => dateTime().nullable()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  TextColumn get status => textEnum<SessionStatus>()();

  /// Time mode: the block bought at start (price is a snapshot of the rate).
  IntColumn get baseMinutes => integer().nullable()();
  IntColumn get baseAmount => integer().withDefault(const Constant(0))();

  /// Running bill for the table (mode total plus benta).
  IntColumn get total => integer().withDefault(const Constant(0))();
  TextColumn get note => text().nullable()();

  /// Short reference shown to people, like 0421-04 (month, day, number of the day).
  TextColumn get ref => text().nullable()();
  TextColumn get openedBy => text().nullable()();
}

class SessionExtensions extends Table with BaseColumns {
  TextColumn get sessionId => text().references(Sessions, #id)();
  IntColumn get minutes => integer()();
  IntColumn get amount => integer()();
}

class SessionGames extends Table with BaseColumns {
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get gameTypeId => text().references(GameTypes, #id)();
  IntColumn get qty => integer()();
  IntColumn get unitPrice => integer()();
  IntColumn get amount => integer()();
}

class RaceDetails extends Table with BaseColumns {
  TextColumn get sessionId => text().references(Sessions, #id)();
  IntColumn get raceTo => integer()();
  IntColumn get betTotal => integer()();
  IntColumn get tableFee => integer()();
  TextColumn get note => text().nullable()();
}

class Products extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get category => text().withDefault(const Constant(''))();
  IntColumn get price => integer()();
  IntColumn get costPrice => integer().nullable()();
  TextColumn get imagePath => text().nullable()();
  IntColumn get stock => integer().withDefault(const Constant(0))();
  IntColumn get lowStockLevel => integer().withDefault(const Constant(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

class ComplimentaryItems extends Table with BaseColumns {
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get qty => integer()();
  IntColumn get costAmount => integer()();
  TextColumn get note => text().nullable()();
}

/// [Sales.status] values.
const saleCompleted = 'completed';
const saleVoided = 'voided';

class Sales extends Table with BaseColumns {
  /// Set when the sale is benta on a table's bill; null for a walk-in sale.
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  IntColumn get total => integer()();
  TextColumn get status => text().withDefault(const Constant(saleCompleted))();
  TextColumn get ref => text().nullable()();
  TextColumn get soldBy => text().nullable()();
}

class SaleItems extends Table with BaseColumns {
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get qty => integer()();
  IntColumn get unitPrice => integer()();
}

/// The inventory log: every stock change as a delta.
class StockMovements extends Table with BaseColumns {
  TextColumn get productId => text().references(Products, #id)();
  IntColumn get delta => integer()();
  IntColumn get stockBefore => integer()();
  IntColumn get stockAfter => integer()();
  TextColumn get reason => textEnum<StockReason>()();
  TextColumn get ref => text().nullable()();

  /// Free-text reason typed by the cashier (adjustments, write-offs).
  TextColumn get note => text().nullable()();
}

class Expenses extends Table with BaseColumns {
  TextColumn get name => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  TextColumn get source => textEnum<ExpenseSource>()();

  /// For complimentary expenses: the complimentary_item that caused it.
  TextColumn get ref => text().nullable()();

  /// Food, Supplies, Utilities, Other (or "Free drinks" for complimentary rows).
  TextColumn get category => text().withDefault(const Constant('Other'))();
}

class Payments extends Table with BaseColumns {
  TextColumn get sessionId => text().nullable().references(Sessions, #id)();
  TextColumn get saleId => text().nullable().references(Sales, #id)();
  IntColumn get amount => integer()();
  IntColumn get cashReceived => integer()();
  IntColumn get changeGiven => integer()();
  DateTimeColumn get paidAt => dateTime()();
}

/// [VoidLogs.refType] values.
///  - paid_table: the table-time part of a paid bill that was refunded (refId = session id)
///  - paid_item: one benta item of a paid bill or walk-in sale that was refunded (refId = sale item id)
///  These two count against income. The next two never reached income:
///  - sale_item: one benta item taken off an open bill
///  - unpaid_session: an unpaid bill written off
const voidRefPaidTable = 'paid_table';
const voidRefPaidItem = 'paid_item';
const voidRefSaleItem = 'sale_item';
const voidRefUnpaid = 'unpaid_session';

/// The void kinds the daily report subtracts from income.
const incomeVoidKinds = [voidRefPaidTable, voidRefPaidItem];

class VoidLogs extends Table with BaseColumns {
  TextColumn get refType => text()();
  TextColumn get refId => text()();
  TextColumn get reason => text()();
  IntColumn get amount => integer()();
  DateTimeColumn get at => dateTime()();

  /// Who did it, and the Owner who approved it with their PIN.
  TextColumn get byName => text().nullable()();
  TextColumn get approvedBy => text().nullable()();
}

/// People who can log in on this tablet. The PIN is the login (no username).
@DataClassName('StaffMember')
class StaffTable extends Table with BaseColumns {
  @override
  String get tableName => 'staff';

  TextColumn get name => text()();
  TextColumn get role => textEnum<StaffRole>()();
  TextColumn get pinSalt => text()();
  TextColumn get pinHash => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

/// Append only.
class AuditLogs extends Table with BaseColumns {
  TextColumn get actor => text()();
  TextColumn get action => text()();
  TextColumn get entity => text()();
  TextColumn get oldValue => text().nullable()();
  TextColumn get newValue => text().nullable()();
  DateTimeColumn get at => dateTime()();
}

/// Small key/value store for device-level settings (device id, alert minutes...).
class AppSettings extends Table {
  TextColumn get settingKey => text()();
  TextColumn get settingValue => text()();

  @override
  Set<Column> get primaryKey => {settingKey};
}
