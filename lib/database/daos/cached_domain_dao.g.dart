// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_domain_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedDomainDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedDomainsTable get cachedDomains => attachedDatabase.cachedDomains;
  CachedDomainDaoManager get managers => CachedDomainDaoManager(this);
}

class CachedDomainDaoManager {
  final _$CachedDomainDaoMixin _db;
  CachedDomainDaoManager(this._db);
  $$CachedDomainsTableTableManager get cachedDomains =>
      $$CachedDomainsTableTableManager(_db.attachedDatabase, _db.cachedDomains);
}
