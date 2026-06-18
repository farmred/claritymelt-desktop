import 'package:drift/drift.dart';
import '../tables.dart';
import '../database.dart';

part 'cached_dns_record_dao.g.dart';

@DriftAccessor(tables: [CachedDnsRecords])
class CachedDnsRecordDao extends DatabaseAccessor<AppDatabase>
    with _$CachedDnsRecordDaoMixin {
  CachedDnsRecordDao(super.db);

  Future<List<CachedDnsRecord>> getByZoneId(String zoneId) {
    return (select(cachedDnsRecords)
          ..where((t) => t.zoneId.equals(zoneId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<List<CachedDnsRecord>> getByProvider(String provider) {
    return (select(cachedDnsRecords)
          ..where((t) => t.provider.equals(provider))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<List<CachedDnsRecord>> getAll() {
    return (select(cachedDnsRecords)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<void> upsertRecord(CachedDnsRecordsCompanion entry) {
    return into(cachedDnsRecords).insertOnConflictUpdate(entry);
  }

  Future<void> upsertRecords(List<CachedDnsRecordsCompanion> entries) {
    return batch((b) {
      b.insertAllOnConflictUpdate(cachedDnsRecords, entries);
    });
  }

  Future<void> deleteByZoneId(String zoneId) {
    return (delete(cachedDnsRecords)..where((t) => t.zoneId.equals(zoneId))).go();
  }

  Future<void> deleteByIds(List<String> ids) {
    return (delete(cachedDnsRecords)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> deleteAll() {
    return delete(cachedDnsRecords).go();
  }
}