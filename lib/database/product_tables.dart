import 'package:drift/drift.dart';

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

/// Links a resource (machine, domain, DNS record, cloudflare worker/page)
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