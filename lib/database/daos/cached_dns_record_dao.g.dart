// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_dns_record_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedDnsRecordDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedDnsRecordsTable get cachedDnsRecords =>
      attachedDatabase.cachedDnsRecords;
  CachedDnsRecordDaoManager get managers => CachedDnsRecordDaoManager(this);
}

class CachedDnsRecordDaoManager {
  final _$CachedDnsRecordDaoMixin _db;
  CachedDnsRecordDaoManager(this._db);
  $$CachedDnsRecordsTableTableManager get cachedDnsRecords =>
      $$CachedDnsRecordsTableTableManager(
        _db.attachedDatabase,
        _db.cachedDnsRecords,
      );
}
