import 'package:drift/drift.dart';
import '../tables.dart';
import '../database.dart';

part 'preferences_dao.g.dart';

@DriftAccessor(tables: [Preferences])
class PreferencesDao extends DatabaseAccessor<AppDatabase>
    with _$PreferencesDaoMixin {
  PreferencesDao(super.db);

  Future<String?> getKey(String key) async {
    final row = await (select(
      preferences,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setKey(String key, String value) {
    return into(preferences).insertOnConflictUpdate(
      PreferencesCompanion.insert(key: key, value: value),
    );
  }

  Future<void> deleteKey(String key) {
    return (delete(preferences)..where((t) => t.key.equals(key))).go();
  }

  Future<String> getEncryptionKey() async {
    return await getKey('encryption_key') ?? '';
  }

  Future<void> setEncryptionKey(String key) async {
    await setKey('encryption_key', key);
  }

  Future<String> getThemeMode() async {
    return await getKey('theme_mode') ?? 'system';
  }

  Future<void> setThemeMode(String mode) async {
    await setKey('theme_mode', mode);
  }
}
