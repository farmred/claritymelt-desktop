// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_machine_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedMachineDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedMachinesTable get cachedMachines => attachedDatabase.cachedMachines;
  CachedMachineDaoManager get managers => CachedMachineDaoManager(this);
}

class CachedMachineDaoManager {
  final _$CachedMachineDaoMixin _db;
  CachedMachineDaoManager(this._db);
  $$CachedMachinesTableTableManager get cachedMachines =>
      $$CachedMachinesTableTableManager(
        _db.attachedDatabase,
        _db.cachedMachines,
      );
}
