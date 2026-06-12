import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/emergency_dao.dart';
import 'daos/services_dao.dart';

part 'database.g.dart';

// ── Table definitions ─────────────────────────────────────────────────────────

/// Offline cache of nearby services — keyed by regionId for bulk invalidation.
class CachedServices extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  TextColumn get subcategory => text().nullable()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get phonePrimary => text().nullable()();
  TextColumn get phoneSecondary => text().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get countryCode => text()();
  TextColumn get stateCode => text().nullable()();
  BoolColumn get is24hr => boolean().withDefault(const Constant(true))();
  IntColumn get trustScore => integer().withDefault(const Constant(1))();
  TextColumn get source => text()();

  /// Geohash-derived region key — used to batch-clear cache per area.
  TextColumn get regionId => text()();

  /// Unix milliseconds when this row was cached — used for expiry.
  IntColumn get cachedAtMs => integer()();
}

/// Local log of emergency sessions — synced to Supabase when online.
class EmergencySessionsLocal extends Table {
  @override
  String get tableName => 'emergency_sessions_local';

  TextColumn get sessionId => text()();
  TextColumn get userPhone => text().nullable()();
  TextColumn get emergencyType => text()();
  TextColumn get victimType => text()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get countryCode => text()();
  IntColumn get victimCount => integer().nullable()();

  /// JSON-serialised List<VictimDetail>.
  TextColumn get victimDetailsJson => text().nullable()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get startedAtMs => integer()();
  IntColumn get resolvedAtMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sessionId};
}

/// Location pings queued for upload while offline.
class LocationPingsLocal extends Table {
  @override
  String get tableName => 'location_pings_local';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  RealColumn get accuracyM => real().nullable()();
  BoolColumn get sentToPolice =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get smsSent => boolean().withDefault(const Constant(false))();
  IntColumn get pinggedAtMs => integer()();
}

/// User profile stored locally — single row with id=1.
class UserProfileLocal extends Table {
  @override
  String get tableName => 'user_profile_local';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get bloodGroup => text().nullable()();
  TextColumn get vehicleNumber => text().nullable()();
  TextColumn get licenseNumber => text().nullable()();
  TextColumn get emergencyContact1 => text().nullable()();
  TextColumn get emergencyContact2 => text().nullable()();

  /// JSON array of trusted-circle phone numbers (up to 5).
  TextColumn get trustedCircleJson => text().nullable()();

  TextColumn get homeCountry =>
      text().withDefault(const Constant('IN'))();
  TextColumn get homeState => text().nullable()();
  BoolColumn get digilockerSynced =>
      boolean().withDefault(const Constant(false))();
  IntColumn get createdAtMs => integer()();
}

// ── Database ──────────────────────────────────────────────────────────────────

@DriftDatabase(
  tables: [
    CachedServices,
    EmergencySessionsLocal,
    LocationPingsLocal,
    UserProfileLocal,
  ],
  daos: [ServicesDao, EmergencyDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  // Migration strategy:
  // When schemaVersion is bumped, add a MigrationStrategy here using
  // from/to migration callbacks. Never drop columns in production —
  // add nullable columns or new tables only.
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          // Future migrations added here as schema evolves.
        },
      );
}

/// Singleton database connection opened lazily via [LazyDatabase].
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'roadsos.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Riverpod provider for the [AppDatabase] singleton.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
