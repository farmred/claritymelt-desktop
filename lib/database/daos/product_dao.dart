import 'package:drift/drift.dart';
import '../tables.dart';
import '../database.dart';

part 'product_dao.g.dart';

@DriftAccessor(tables: [Products, ProductResources])
class ProductDao extends DatabaseAccessor<AppDatabase>
    with _$ProductDaoMixin {
  ProductDao(super.db);

  Future<List<Product>> getAll() {
    return (select(products)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();
  }

  Future<Product?> getById(String id) {
    return (select(products)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<void> insertProduct(ProductsCompanion entry) {
    return into(products).insertOnConflictUpdate(entry);
  }

  Future<void> deleteProduct(String id) {
    return (delete(products)..where((t) => t.id.equals(id))).go();
  }

  Future<List<ProductResource>> getResourcesForProduct(String productId) {
    return (select(productResources)..where((t) => t.productId.equals(productId))).get();
  }

  Future<void> insertResource(ProductResourcesCompanion entry) {
    return into(productResources).insertOnConflictUpdate(entry);
  }

  Future<void> deleteResource(String id) {
    return (delete(productResources)..where((t) => t.id.equals(id))).go();
  }

  Future<void> deleteResourcesForProduct(String productId) {
    return (delete(productResources)..where((t) => t.productId.equals(productId))).go();
  }

  Future<void> deleteResourcesByType(String resourceType) {
    return (delete(productResources)..where((t) => t.resourceType.equals(resourceType))).go();
  }
}