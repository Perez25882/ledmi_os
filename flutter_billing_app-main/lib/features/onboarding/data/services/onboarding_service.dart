import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/barcode_lookup_result.dart';
import '../../../../core/supabase/supabase_client.dart';

/// Lightweight row model for a `business_types` entry.
class BusinessType {
  final String id;
  final String name;
  final String? icon;

  const BusinessType({
    required this.id,
    required this.name,
    this.icon,
  });

  factory BusinessType.fromRow(Map<String, dynamic> row) => BusinessType(
        id: row['id'] as String,
        name: row['name'] as String,
        icon: row['icon'] as String?,
      );
}

/// Lightweight row model for a `starter_catalog_templates` entry.
class StarterCatalogTemplate {
  final String id;
  final String businessType;
  final String name;
  final String? barcode;
  final String category;
  final double suggestedPrice;
  final double? suggestedCost;
  final String unit;
  final String? imageUrl;
  final int sortOrder;

  const StarterCatalogTemplate({
    required this.id,
    required this.businessType,
    required this.name,
    this.barcode,
    required this.category,
    required this.suggestedPrice,
    this.suggestedCost,
    this.unit = 'piece',
    this.imageUrl,
    this.sortOrder = 0,
  });

  factory StarterCatalogTemplate.fromRow(Map<String, dynamic> row) =>
      StarterCatalogTemplate(
        id: row['id'] as String,
        businessType: row['business_type'] as String,
        name: row['name'] as String,
        barcode: row['barcode'] as String?,
        category: row['category'] as String,
        suggestedPrice: (row['suggested_price'] as num).toDouble(),
        suggestedCost: (row['suggested_cost'] as num?)?.toDouble(),
        unit: (row['unit'] as String?) ?? 'piece',
        imageUrl: row['image_url'] as String?,
        sortOrder: (row['sort_order'] as int?) ?? 0,
      );
}

/// Onboarding data service — talks to Supabase for business-type selection,
/// starter-catalog loading, and shelf-scan product creation.
class OnboardingService {
  final SupabaseClient _client;

  OnboardingService({SupabaseClient? client})
      : _client = client ?? SupabaseClientManager.client;

  /// Fetches all business types ordered by name.
  Future<List<BusinessType>> getBusinessTypes() async {
    final rows = await _client
        .from('business_types')
        .select()
        .order('name') as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .map(BusinessType.fromRow)
        .toList();
  }

  /// Fetches starter catalog templates for [businessType], ordered by sort_order.
  Future<List<StarterCatalogTemplate>> getStarterCatalog(
    String businessType,
  ) async {
    final rows = await _client
        .from('starter_catalog_templates')
        .select()
        .eq('business_type', businessType)
        .order('sort_order') as List<dynamic>;
    return rows
        .cast<Map<String, dynamic>>()
        .map(StarterCatalogTemplate.fromRow)
        .toList();
  }

  /// Persists the selected business type on the business row.
  Future<void> saveBusinessType({
    required String businessId,
    required String businessType,
  }) async {
    await _client
        .from('businesses')
        .update({'business_type': businessType}).eq('id', businessId);
  }

  /// Bulk-inserts the selected starter templates into `products` and creates
  /// corresponding `inventory` rows (quantity 0) for [branchId].
  ///
  /// Returns the list of created product IDs.
  Future<List<String>> loadStarterCatalogIntoProducts({
    required String businessId,
    required String branchId,
    required List<StarterCatalogTemplate> selectedTemplates,
  }) async {
    if (selectedTemplates.isEmpty) return [];

    final productRows = selectedTemplates.map((t) {
      return {
        'business_id': businessId,
        'name': t.name,
        'barcode': t.barcode,
        'selling_price': t.suggestedPrice,
        'cost_price': t.suggestedCost ?? 0,
        'reorder_threshold': 10,
      };
    }).toList();

    final inserted = await _client
        .from('products')
        .insert(productRows)
        .select('id') as List<dynamic>;

    final productIds = inserted
        .cast<Map<String, dynamic>>()
        .map((row) => row['id'] as String)
        .toList();

    if (productIds.isEmpty) return [];

    final inventoryRows = productIds.map((pid) {
      return {
        'product_id': pid,
        'business_id': businessId,
        'branch_id': branchId,
        'quantity': 0,
      };
    }).toList();

    await _client.from('inventory').insert(inventoryRows);

    return productIds;
  }

  /// Marks onboarding as complete for [businessId].
  Future<void> completeOnboarding(String businessId) async {
    await _client
        .from('businesses')
        .update({'onboarding_completed': true}).eq('id', businessId);
  }

  /// Checks whether onboarding has been completed for [businessId].
  Future<bool> isOnboardingCompleted(String businessId) async {
    final rows = await _client
        .from('businesses')
        .select('onboarding_completed')
        .eq('id', businessId)
        .limit(1) as List<dynamic>;
    if (rows.isEmpty) return true;
    final row = rows.first as Map<String, dynamic>;
    return row['onboarding_completed'] as bool? ?? false;
  }

  /// Inserts a product derived from a barcode lookup (or manual entry) and
  /// creates an inventory row with [stockQty] for [branchId].
  ///
  /// Returns the new product ID.
  Future<String> addProductFromBarcode({
    required String businessId,
    required String branchId,
    required String barcode,
    BarcodeLookupResult? lookupResult,
    required double price,
    required int stockQty,
    String? nameOverride,
  }) async {
    final name = nameOverride?.isNotEmpty == true
        ? nameOverride!
        : (lookupResult?.name ?? 'Unknown Product');

    final inserted = await _client.from('products').insert({
      'business_id': businessId,
      'name': name,
      'barcode': barcode,
      'selling_price': price,
      'cost_price': 0,
      'reorder_threshold': 10,
    }).select('id') as List<dynamic>;

    final productId = (inserted.first as Map<String, dynamic>)['id'] as String;

    await _client.from('inventory').insert({
      'product_id': productId,
      'business_id': businessId,
      'branch_id': branchId,
      'quantity': stockQty,
    });

    return productId;
  }

  /// Looks up a product by barcode within the current business catalog.
  /// Returns the product row (id, name, selling_price) or null if not found.
  Future<Map<String, dynamic>?> findProductByBarcode({
    required String businessId,
    required String barcode,
  }) async {
    final rows = await _client
        .from('products')
        .select('id, name, selling_price, barcode')
        .eq('business_id', businessId)
        .eq('barcode', barcode)
        .limit(1) as List<dynamic>;
    if (rows.isEmpty) return null;
    return rows.first as Map<String, dynamic>;
  }

  /// Sets the stock quantity for an existing product/branch inventory row.
  /// Inserts the inventory row if it does not yet exist.
  Future<void> setInventoryQuantity({
    required String businessId,
    required String branchId,
    required String productId,
    required int quantity,
  }) async {
    final existing = await _client
        .from('inventory')
        .select('product_id')
        .eq('product_id', productId)
        .eq('branch_id', branchId)
        .limit(1) as List<dynamic>;

    if (existing.isEmpty) {
      await _client.from('inventory').insert({
        'product_id': productId,
        'business_id': businessId,
        'branch_id': branchId,
        'quantity': quantity,
      });
    } else {
      await _client
          .from('inventory')
          .update({'quantity': quantity}).eq('product_id', productId).eq(
              'branch_id', branchId);
    }
  }
}
