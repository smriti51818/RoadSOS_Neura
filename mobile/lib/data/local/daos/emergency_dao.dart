import 'package:drift/drift.dart';

import '../database.dart';

part 'emergency_dao.g.dart';

/// DAO for managing emergency sessions and location pings in local SQLite.
@DriftAccessor(tables: [EmergencySessionsLocal, LocationPingsLocal])
class EmergencyDao extends DatabaseAccessor<AppDatabase>
    with _$EmergencyDaoMixin {
  EmergencyDao(super.db);

  /// Inserts a new emergency session.
  Future<void> insertSession(EmergencySessionsLocalCompanion session) async {
    await into(emergencySessionsLocal).insertOnConflictUpdate(session);
  }

  /// Returns the most recently started active session, or null if none.
  Future<EmergencySessionsLocalData?> getActiveSession() async {
    return (select(emergencySessionsLocal)
          ..where((s) => s.isActive.equals(true))
          ..orderBy([(s) => OrderingTerm.desc(s.startedAtMs)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Marks a session as resolved and records the resolution timestamp.
  Future<void> markSessionResolved(String sessionId) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await (update(emergencySessionsLocal)
          ..where((s) => s.sessionId.equals(sessionId)))
        .write(EmergencySessionsLocalCompanion(
      isActive: const Value(false),
      resolvedAtMs: Value(nowMs),
    ));
  }

  /// Inserts a new location ping for an active session.
  Future<void> insertPing(LocationPingsLocalCompanion ping) async {
    await into(locationPingsLocal).insert(ping);
  }

  /// Returns all pings associated with [sessionId] ordered by time ascending.
  Future<List<LocationPingsLocalData>> getPingsForSession(
    String sessionId,
  ) async {
    return (select(locationPingsLocal)
          ..where((p) => p.sessionId.equals(sessionId))
          ..orderBy([(p) => OrderingTerm.asc(p.pinggedAtMs)]))
        .get();
  }

  /// Updates victim count and serialised details on an existing session.
  Future<void> updateVictimDetails(
    String sessionId,
    int victimCount,
    String victimDetailsJson,
  ) async {
    await (update(emergencySessionsLocal)
          ..where((s) => s.sessionId.equals(sessionId)))
        .write(EmergencySessionsLocalCompanion(
      victimCount: Value(victimCount),
      victimDetailsJson: Value(victimDetailsJson),
    ));
  }

  // ── Module 5: Offline ping sync ────────────────────────────────────────────

  /// Returns all pings not yet uploaded to the backend.
  ///
  /// Uses [sentToPolice] as the API-sync flag — false means unsynced.
  /// (Module 6 will introduce per-channel flags; for now this column is
  /// repurposed as a general "sent to server" marker.)
  Future<List<LocationPingsLocalData>> getUnsyncedPings() async {
    return (select(locationPingsLocal)
          ..where((p) => p.sentToPolice.equals(false))
          ..orderBy([(p) => OrderingTerm.asc(p.pinggedAtMs)]))
        .get();
  }

  /// Marks a single ping as synced by setting [sentToPolice] = true.
  Future<void> markPingSynced(int pingId) async {
    await (update(locationPingsLocal)
          ..where((p) => p.id.equals(pingId)))
        .write(const LocationPingsLocalCompanion(
      sentToPolice: Value(true),
    ));
  }
}
