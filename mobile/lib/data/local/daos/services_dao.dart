import 'package:drift/drift.dart';

import '../database.dart';

part 'services_dao.g.dart';

/// DAO for reading and writing cached service records.
@DriftAccessor(tables: [CachedServices])
class ServicesDao extends DatabaseAccessor<AppDatabase>
    with _$ServicesDaoMixin {
  ServicesDao(super.db);

  /// Inserts or replaces a cached service record.
  Future<void> insertService(CachedServicesCompanion service) async {
    await into(cachedServices).insertOnConflictUpdate(service);
  }

  /// Returns all cached services for the given [regionId].
  Future<List<CachedService>> getServicesByRegion(String regionId) async {
    return (select(cachedServices)
          ..where((s) => s.regionId.equals(regionId)))
        .get();
  }

  /// Returns nearby services filtered by bounding box, category, and trust score.
  ///
  /// Bounding box is an approximation:
  ///   1 degree latitude ≈ 111 km, so radiusDeg = radiusKm / 111.
  Future<List<CachedService>> getNearbyServices({
    required double lat,
    required double lng,
    required double radiusKm,
    String? category,
    int minTrustScore = 1,
  }) async {
    final radiusDeg = radiusKm / 111.0;
    final minLat = lat - radiusDeg;
    final maxLat = lat + radiusDeg;
    final minLng = lng - radiusDeg;
    final maxLng = lng + radiusDeg;

    final query = select(cachedServices)
      ..where((s) =>
          s.lat.isBetweenValues(minLat, maxLat) &
          s.lng.isBetweenValues(minLng, maxLng) &
          s.trustScore.isBiggerOrEqualValue(minTrustScore))
      ..orderBy([(s) => OrderingTerm.desc(s.trustScore)])
      ..limit(20);

    if (category != null) {
      query.where((s) => s.category.equals(category));
    }

    return query.get();
  }

  /// Deletes cached rows older than [olderThanDays] days.
  Future<void> clearOldCache(int olderThanDays) async {
    final cutoffMs = DateTime.now()
            .subtract(Duration(days: olderThanDays))
            .millisecondsSinceEpoch;
    await (delete(cachedServices)
          ..where((s) => s.cachedAtMs.isSmallerThanValue(cutoffMs)))
        .go();
  }

  /// Returns the number of cached services for the given [regionId].
  Future<int> countByRegion(String regionId) async {
    final count = countAll();
    final query = selectOnly(cachedServices)
      ..addColumns([count])
      ..where(cachedServices.regionId.equals(regionId));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Removes all cached services for the given [regionId].
  Future<void> clearRegion(String regionId) async {
    await (delete(cachedServices)
          ..where((s) => s.regionId.equals(regionId)))
        .go();
  }
}
