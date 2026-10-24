import 'package:drift/drift.dart';

import '../domain/enums.dart';
import 'audit.dart';
import 'database.dart';

/// Pool tables and where they stand on the floor map. Each branch keeps its own map.
class TableRepository {
  TableRepository(this.db);

  final AppDatabase db;

  /// Moves a table on the map (grid units). Logged, because the map is the Owner's.
  Future<void> moveTable({
    required String id,
    required int x,
    required int y,
    required DateTime now,
  }) {
    return db.transaction(() async {
      final t = await (db.select(db.poolTables)..where((p) => p.id.equals(id))).getSingle();
      if (t.mapX == x && t.mapY == y) return;
      await (db.update(db.poolTables)..where((p) => p.id.equals(id))).write(
        PoolTablesCompanion(
          mapX: Value(x),
          mapY: Value(y),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await writeAudit(db,
          action: 'table_moved',
          entity: 'table:${t.label}',
          oldValue: '${t.mapX},${t.mapY}',
          newValue: '$x,$y',
          now: now);
    });
  }

  /// Sets a table's size on the map (grid units, 1 to 4 each side). Turning a table
  /// is resizing it with width and height swapped.
  Future<void> resizeTable({
    required String id,
    required int w,
    required int h,
    required DateTime now,
  }) {
    final width = w.clamp(1, 4);
    final height = h.clamp(1, 4);
    return db.transaction(() async {
      final t = await (db.select(db.poolTables)..where((p) => p.id.equals(id))).getSingle();
      if (t.w == width && t.h == height) return;
      await (db.update(db.poolTables)..where((p) => p.id.equals(id))).write(
        PoolTablesCompanion(
          w: Value(width),
          h: Value(height),
          updatedAt: Value(now),
          synced: const Value(false),
        ),
      );
      await writeAudit(db,
          action: 'table_resized',
          entity: 'table:${t.label}',
          oldValue: '${t.w}x${t.h}',
          newValue: '${width}x$height',
          now: now);
    });
  }

  // Zones: the counter, the entrance and other non-table things on the map.

  Future<void> moveZone({required String id, required int x, required int y, required DateTime now}) {
    return db.transaction(() async {
      final z = await (db.select(db.floorZones)..where((p) => p.id.equals(id))).getSingle();
      if (z.mapX == x && z.mapY == y) return;
      await (db.update(db.floorZones)..where((p) => p.id.equals(id))).write(FloorZonesCompanion(
        mapX: Value(x),
        mapY: Value(y),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await writeAudit(db,
          action: 'zone_moved',
          entity: 'zone:${z.label}',
          oldValue: '${z.mapX},${z.mapY}',
          newValue: '$x,$y',
          now: now);
    });
  }

  /// Zones can be wider than tables: up to 6 by 3.
  Future<void> resizeZone({required String id, required int w, required int h, required DateTime now}) {
    final width = w.clamp(1, 6);
    final height = h.clamp(1, 3);
    return db.transaction(() async {
      final z = await (db.select(db.floorZones)..where((p) => p.id.equals(id))).getSingle();
      if (z.w == width && z.h == height) return;
      await (db.update(db.floorZones)..where((p) => p.id.equals(id))).write(FloorZonesCompanion(
        w: Value(width),
        h: Value(height),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await writeAudit(db,
          action: 'zone_resized',
          entity: 'zone:${z.label}',
          oldValue: '${z.w}x${z.h}',
          newValue: '${width}x$height',
          now: now);
    });
  }

  Future<void> addZone({required String label, required DateTime now}) {
    if (label.trim().isEmpty) throw ArgumentError('Name is required');
    return db.transaction(() async {
      final tables = await (db.select(db.poolTables)..where((t) => t.deletedAt.isNull())).get();
      final zones = await (db.select(db.floorZones)..where((t) => t.deletedAt.isNull())).get();
      final bottom = [
        ...tables.map((t) => t.mapY + t.h),
        ...zones.map((z) => z.mapY + z.h),
      ].fold<int>(0, (m, v) => v > m ? v : m);
      await db.into(db.floorZones).insert(FloorZonesCompanion.insert(
            label: label.trim(),
            mapX: const Value(2),
            mapY: Value(bottom),
            w: const Value(2),
            h: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await writeAudit(db, action: 'zone_added', entity: 'zone:${label.trim()}', now: now);
    });
  }

  Future<void> removeZone({required String id, required DateTime now}) {
    return db.transaction(() async {
      final z = await (db.select(db.floorZones)..where((p) => p.id.equals(id))).getSingle();
      await (db.update(db.floorZones)..where((p) => p.id.equals(id))).write(FloorZonesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await writeAudit(db, action: 'zone_removed', entity: 'zone:${z.label}', now: now);
    });
  }

  /// Adds a table to the floor, below the others. Drag it into place on the map.
  Future<void> addTable({required String label, required DateTime now}) {
    if (label.trim().isEmpty) throw ArgumentError('Name is required');
    return db.transaction(() async {
      final clash = await (db.select(db.poolTables)
            ..where((t) => t.label.equals(label.trim()) & t.deletedAt.isNull()))
          .get();
      if (clash.isNotEmpty) throw StateError('There is already a table named ${label.trim()}');
      final all = await (db.select(db.poolTables)..where((t) => t.deletedAt.isNull())).get();
      final bottom = all.fold<int>(0, (m, t) => t.mapY + t.h > m ? t.mapY + t.h : m);
      await db.into(db.poolTables).insert(PoolTablesCompanion.insert(
            label: label.trim(),
            mapX: const Value(2),
            mapY: Value(bottom),
            w: const Value(2),
            h: const Value(1),
            createdAt: Value(now),
            updatedAt: Value(now),
          ));
      await writeAudit(db, action: 'table_added', entity: 'table:${label.trim()}', now: now);
    });
  }

  /// Takes a table off the floor (kept in the database). A table in use cannot be removed.
  Future<void> removeTable({required String id, required DateTime now}) {
    return db.transaction(() async {
      final t = await (db.select(db.poolTables)..where((p) => p.id.equals(id))).getSingle();
      final open = await (db.select(db.sessions)
            ..where((s) =>
                s.tableId.equals(id) &
                s.status.isInValues([SessionStatus.running, SessionStatus.waitingToPay])))
          .get();
      if (open.isNotEmpty) throw StateError('${t.label} is in use');
      await (db.update(db.poolTables)..where((p) => p.id.equals(id))).write(PoolTablesCompanion(
        active: const Value(false),
        deletedAt: Value(now),
        updatedAt: Value(now),
        synced: const Value(false),
      ));
      await writeAudit(db, action: 'table_removed', entity: 'table:${t.label}', now: now);
    });
  }
}
