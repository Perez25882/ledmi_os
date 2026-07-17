import '../../../../core/data/hive_database.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../product/data/models/product_model.dart';

class SupabaseSyncService {
  final _client = SupabaseClientManager.client;

  Future<void> syncCatalog() async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;

    if (businessId == null || branchId == null) {
      throw Exception('Business and branch must be selected before syncing');
    }

    final response = await _client
        .from('products')
        .select('''
          id,
          name,
          barcode,
          selling_price,
          inventory!inner(quantity)
        ''')
        .eq('business_id', businessId)
        .eq('inventory.branch_id', branchId)
        .isFilter('deleted_at', null);

    final rows = response as List<dynamic>;

    final productBox = HiveDatabase.productBox;
    await productBox.clear();

    for (final row in rows) {
      final product = row as Map<String, dynamic>;
      final inventory = product['inventory'] as Map<String, dynamic>?;
      final quantity = (inventory?['quantity'] as num?)?.toInt() ?? 0;

      final model = ProductModel.fromSupabase(product, branchQuantity: quantity);
      await productBox.put(model.id, model);
    }
  }
}
