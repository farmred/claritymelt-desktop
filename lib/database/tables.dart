import 'package:drift/drift.dart';

/// Provider credential types matching the original app.
enum ProviderType { ovh, hetzner, namecheap, cloudflare }

/// Provider credentials stored per-organization, encrypted at rest.
class ProviderCredentials extends Table {
  TextColumn get id => text()();
  TextColumn get provider => text()(); // ovh, hetzner, namecheap, cloudflare
  TextColumn get label => text()();
  TextColumn get credentials => text()(); // AES-256-GCM encrypted JSON blob
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached machine data from provider APIs.
class CachedMachines extends Table {
  TextColumn get id => text()();
  TextColumn get providerId => text()(); // Original provider resource ID (e.g. "ovh-12345")
  TextColumn get provider => text()(); // "ovh", "ovh-dedicated", "hetzner"
  TextColumn get name => text()();
  TextColumn get alias => text().nullable()(); // User-assigned friendly name
  TextColumn get status => text().withDefault(const Constant('unknown'))();
  TextColumn get ipAddresses => text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get region => text().withDefault(const Constant(''))();
  TextColumn get flavor => text().nullable()();
  TextColumn get image => text().nullable()();
  TextColumn get raw => text().nullable()(); // Full provider response JSON
  TextColumn get uncloudMachineId => text().nullable()(); // Uncloud machine ID (e.g. "fb307942f2421d182608fa64aced3eed")
  TextColumn get uncloudContext => text().nullable()(); // Uncloud context name (e.g. "default-1")
  DateTimeColumn get lastSyncedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached domain data from provider APIs.
class CachedDomains extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get provider => text()(); // "namecheap", "cloudflare", "ovh", "external"
  TextColumn get nameservers => text().withDefault(const Constant('[]'))(); // JSON array
  TextColumn get cfZoneId => text().nullable()();
  TextColumn get cfStatus => text().nullable()();
  TextColumn get cfNameservers => text().withDefault(const Constant('[]'))(); // JSON array of CF-assigned nameservers
  TextColumn get dnsProvider => text().nullable()(); // Who manages DNS: "cloudflare", "ovh", "namecheap"
  TextColumn get expires => text().nullable()();
  TextColumn get raw => text().nullable()(); // Full provider response JSON
  DateTimeColumn get lastSyncedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached DNS records from Cloudflare / OVH / Namecheap.
class CachedDnsRecords extends Table {
  TextColumn get id => text()();
  TextColumn get zoneId => text()();
  TextColumn get zoneName => text().withDefault(const Constant(''))();
  TextColumn get provider => text().withDefault(const Constant('cloudflare'))(); // "cloudflare", "ovh", "namecheap"
  TextColumn get type => text()();
  TextColumn get name => text()();
  TextColumn get content => text()();
  IntColumn get ttl => integer().withDefault(const Constant(1))();
  BoolColumn get proxied => boolean().withDefault(const Constant(false))();
  IntColumn get priority => integer().nullable()();
  DateTimeColumn get lastSyncedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key-value preferences store.
class Preferences extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Products group infrastructure resources (machines, domains, DNS) together.
/// A product represents a deployed service/project — e.g. "ClarityMelt API",
/// "Customer Portal", etc.
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Links a resource (machine, domain, DNS zone, cloudflare worker/page)
/// to a product.
class ProductResources extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text()();
  TextColumn get resourceType => text()(); // "machine", "domain", "dns_zone", "cloudflare_worker", "cloudflare_page"
  TextColumn get resourceId => text()(); // Machine ID, domain name, zone ID, etc.
  TextColumn get role => text().withDefault(const Constant('primary'))(); // "primary", "secondary", "cdn", etc.
  TextColumn get metadata => text().withDefault(const Constant('{}'))(); // JSON blob for extra info
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Notes attached to machines or domains.
class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get resourceType => text()(); // "machine" or "domain"
  TextColumn get resourceId => text()(); // Machine ID or domain ID
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tasks (checklist items) attached to machines or domains.
class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get resourceType => text()(); // "machine" or "domain"
  TextColumn get resourceId => text()(); // Machine ID or domain ID
  TextColumn get title => text()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}