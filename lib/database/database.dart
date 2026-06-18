import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables.dart';
// product_tables.dart merged into tables.dart
import 'daos/provider_credential_dao.dart';
import 'daos/cached_machine_dao.dart';
import 'daos/cached_domain_dao.dart';
import 'daos/cached_dns_record_dao.dart';
import 'daos/preferences_dao.dart';
import 'daos/product_dao.dart';
import 'daos/notes_dao.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    ProviderCredentials,
    CachedMachines,
    CachedDomains,
    CachedDnsRecords,
    Preferences,
    Products,
    ProductResources,
    Notes,
    Tasks,
  ],
  daos: [
    ProviderCredentialDao,
    CachedMachineDao,
    CachedDomainDao,
    CachedDnsRecordDao,
    PreferencesDao,
    ProductDao,
    NotesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Insert default preferences
        await into(preferences).insert(
          PreferencesCompanion.insert(key: 'encryption_key', value: ''),
        );
        await into(preferences).insert(
          PreferencesCompanion.insert(key: 'theme_mode', value: 'system'),
        );
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(cachedDomains, cachedDomains.dnsProvider);
          await m.addColumn(cachedDnsRecords, cachedDnsRecords.provider);
        }
        if (from < 3) {
          await m.addColumn(cachedDomains, cachedDomains.cfNameservers);
        }
        if (from < 4) {
          await m.createTable(products);
          await m.createTable(productResources);
        }
        if (from < 5) {
          await m.addColumn(cachedMachines, cachedMachines.alias);
        }
        if (from < 6) {
          await m.createTable(notes);
          await m.createTable(tasks);
        }
        if (from < 7) {
          await m.addColumn(cachedMachines, cachedMachines.uncloudMachineId);
          await m.addColumn(cachedMachines, cachedMachines.uncloudContext);
        }
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, 'claritymelt.db'));
    return NativeDatabase.createInBackground(file);
  });
}