import 'package:drift/drift.dart';
import '../tables.dart';
import '../database.dart';

part 'provider_credential_dao.g.dart';

@DriftAccessor(tables: [ProviderCredentials])
class ProviderCredentialDao extends DatabaseAccessor<AppDatabase>
    with _$ProviderCredentialDaoMixin {
  ProviderCredentialDao(super.db);

  Future<List<ProviderCredential>> getAll() {
    return (select(providerCredentials)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<List<ProviderCredential>> getByProvider(String provider) {
    return (select(providerCredentials)
          ..where((t) => t.provider.equals(provider)))
        .get();
  }

  Future<ProviderCredential?> getById(String id) {
    return (select(providerCredentials)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<void> insertCredential(ProviderCredentialsCompanion entry) {
    return into(providerCredentials).insert(entry);
  }

  Future<void> deleteCredential(String id) {
    return (delete(providerCredentials)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteAll() {
    return delete(providerCredentials).go();
  }
}