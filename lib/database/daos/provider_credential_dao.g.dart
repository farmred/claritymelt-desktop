// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'provider_credential_dao.dart';

// ignore_for_file: type=lint
mixin _$ProviderCredentialDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProviderCredentialsTable get providerCredentials =>
      attachedDatabase.providerCredentials;
  ProviderCredentialDaoManager get managers =>
      ProviderCredentialDaoManager(this);
}

class ProviderCredentialDaoManager {
  final _$ProviderCredentialDaoMixin _db;
  ProviderCredentialDaoManager(this._db);
  $$ProviderCredentialsTableTableManager get providerCredentials =>
      $$ProviderCredentialsTableTableManager(
        _db.attachedDatabase,
        _db.providerCredentials,
      );
}
