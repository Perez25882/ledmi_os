import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';

class RefundableItem {
  final String id;
  final String productName;
  final int quantity;
  final int refundedQuantity;
  final double unitPrice;

  RefundableItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.refundedQuantity,
    required this.unitPrice,
  });

  int get maxRefundable => quantity - refundedQuantity;
}

class RefundService {
  final _client = SupabaseClientManager.client;

  Future<List<RefundableItem>> getRefundableItems(String saleId) async {
    final businessId = SessionManager.businessId;
    if (businessId == null) throw Exception('No business selected');

    final response = await _client
        .from('sale_items')
        .select('id, quantity, unit_price, products(name)')
        .eq('sale_id', saleId);

    final saleItems = response as List<dynamic>;

    final refundResponse = await _client
        .from('refund_items')
        .select('sale_item_id, quantity, refunds!inner(sale_id, status)')
        .eq('refunds.sale_id', saleId)
        .eq('refunds.status', 'completed');

    final refunds = refundResponse as List<dynamic>? ?? [];
    final refunded = <String, int>{};
    for (final r in refunds) {
      final id = r['sale_item_id'] as String;
      refunded[id] = (refunded[id] ?? 0) + (r['quantity'] as int);
    }

    return saleItems.map((item) {
      final product = item['products'] as Map<String, dynamic>?;
      final id = item['id'] as String;
      return RefundableItem(
        id: id,
        productName: product?['name'] as String? ?? 'Unknown',
        quantity: item['quantity'] as int,
        refundedQuantity: refunded[id] ?? 0,
        unitPrice: (item['unit_price'] as num).toDouble(),
      );
    }).toList();
  }

  Future<String> processRefund({
    required String saleId,
    required Map<String, int> items,
    String? reason,
  }) async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    final userId = _client.auth.currentUser?.id;

    if (businessId == null || branchId == null || userId == null) {
      throw Exception('Session not initialized');
    }

    final payload = items.entries
        .where((e) => e.value > 0)
        .map((e) => {'sale_item_id': e.key, 'quantity': e.value})
        .toList();

    if (payload.isEmpty) throw Exception('No items selected for refund');

    final response = await _client.rpc('process_refund', params: {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      'p_cashier_id': userId,
      'p_sale_id': saleId,
      'p_items': payload,
      'p_reason': reason,
    });

    if (response.error != null) {
      throw Exception(response.error!.message);
    }

    return response.data as String;
  }
}
