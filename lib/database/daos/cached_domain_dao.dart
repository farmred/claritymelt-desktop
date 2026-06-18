import 'package:drift/drift.dart';
import '../tables.dart';
import '../database.dart';

part 'cached_domain_dao.g.dart';

@DriftAccessor(tables: [CachedDomains])
class CachedDomainDao extends DatabaseAccessor<AppDatabase>
    with _$CachedDomainDaoMixin {
  CachedDomainDao(super.db);

  Future<List<CachedDomain>> getAll() {
    return (select(cachedDomains)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<CachedDomain?> getByName(String name) {
    return (select(cachedDomains)..where((t) => t.name.equals(name)))
        .getSingleOrNull();
  }

  Future<void> upsertDomain(CachedDomainsCompanion entry) {
    return into(cachedDomains).insertOnConflictUpdate(entry);
  }

  Future<void> upsertDomains(List<CachedDomainsCompanion> entries) {
    return batch((b) {
      b.insertAllOnConflictUpdate(cachedDomains, entries);
    });
  }

  Future<void> deleteByName(String name) {
    return (delete(cachedDomains)..where((t) => t.name.equals(name))).go();
  }

  Future<void> deleteByIds(List<String> ids) {
    return (delete(cachedDomains)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> deleteAll() {
    return delete(cachedDomains).go();
  }
}