import 'package:drift/drift.dart';
import '../tables.dart';
import '../database.dart';

part 'cached_machine_dao.g.dart';

@DriftAccessor(tables: [CachedMachines])
class CachedMachineDao extends DatabaseAccessor<AppDatabase>
    with _$CachedMachineDaoMixin {
  CachedMachineDao(super.db);

  Future<List<CachedMachine>> getAll() {
    return (select(cachedMachines)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<CachedMachine?> getById(String id) {
    return (select(cachedMachines)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> upsertMachine(CachedMachinesCompanion entry) {
    return into(cachedMachines).insertOnConflictUpdate(entry);
  }

  Future<void> upsertMachines(List<CachedMachinesCompanion> entries) {
    return batch((b) {
      b.insertAllOnConflictUpdate(cachedMachines, entries);
    });
  }

  Future<void> deleteByIds(List<String> ids) {
    return (delete(cachedMachines)..where((t) => t.id.isIn(ids))).go();
  }

  Future<void> deleteAll() {
    return delete(cachedMachines).go();
  }

  /// Update the Uncloud machine ID and context for a cached machine.
  Future<void> setUncloudId(String machineId, String? uncloudMachineId, String? uncloudContext) {
    return (update(cachedMachines)..where((t) => t.id.equals(machineId)))
        .write(CachedMachinesCompanion(
          uncloudMachineId: Value(uncloudMachineId),
          uncloudContext: Value(uncloudContext),
        ));
  }

  /// Find a cached machine whose IPs contain the given IP.
  Future<CachedMachine?> findByIp(String ip) async {
    final all = await getAll();
    for (final m in all) {
      // ipAddresses is stored as JSON array
      try {
        final ips = (m.ipAddresses);
        if (ips.contains(ip)) return m;
      } catch (_) {}
    }
    return null;
  }
}