import 'package:uuid/uuid.dart';

import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../billing/domain/entities/cart_item.dart';
import '../../../sync/data/services/offline_queue_service.dart';

class CheckoutResult {
  final String? saleId;
  final String? queueId;
  final bool wasQueued;

  CheckoutResult({this.saleId, this.queueId, this.wasQueued = false});
}

class CheckoutService {
  final _client = SupabaseClientManager.client;
  final _uuid = const Uuid();
  final OfflineQueueService _offlineQueueService;

  CheckoutService({OfflineQueueService? offlineQueueService})
      : _offlineQueueService = offlineQueueService ?? OfflineQueueService();

  String _newIdempotencyKey() => _uuid.v4();

  List<Map<String, dynamic>> _buildItemsPayload(List<CartItem> items) {
    return items.map((item) => {
          'product_id': item.product.id,
          'quantity': item.quantity,
          'unit_price': item.product.price,
        }).toList();
  }

  double _computeTotal(List<CartItem> items, double discount) {
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.total);
    return (subtotal - discount).clamp(0, double.infinity).toDouble();
  }

  Future<CheckoutResult> processCashCheckout({
    required List<CartItem> items,
    required double discount,
  }) async {
    final total = _computeTotal(items, discount);
    final idempotencyKey = _newIdempotencyKey();
    final itemsJson = _buildItemsPayload(items);

    if (await _offlineQueueService.isOnline()) {
      try {
        final saleId = await _processCashCheckoutOnline(
          idempotencyKey: idempotencyKey,
          itemsJson: itemsJson,
          total: total,
        );
        return CheckoutResult(saleId: saleId);
      } on Exception catch (_) {
        // Fall through to offline queue if the RPC fails for any reason.
      }
    }

    final op = await _offlineQueueService.enqueueSale(
      items: items,
      discount: discount,
      total: total,
    );
    return CheckoutResult(queueId: op.id, wasQueued: true);
  }

  Future<String> _processCashCheckoutOnline({
    required String idempotencyKey,
    required List<Map<String, dynamic>> itemsJson,
    required double total,
  }) async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    final userId = _client.auth.currentUser?.id;

    if (businessId == null || branchId == null || userId == null) {
      throw Exception('Session not initialized. Please select a branch.');
    }

    final response = await _client.rpc('process_checkout_cash', params: {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      'p_cashier_id': userId,
      'p_idempotency_key': idempotencyKey,
      'p_items': itemsJson,
      'p_total_amount': total,
    });

    if (response.error != null) {
      throw Exception(response.error!.message);
    }

    return response.data as String;
  }

  Future<String> processCashCheckoutOffline({
    required String idempotencyKey,
    required List<Map<String, dynamic>> itemsJson,
    required double discount,
  }) async {
    final total = itemsJson.fold<double>(
      0,
      (sum, item) =>
          sum + ((item['unit_price'] as num).toDouble() * (item['quantity'] as int)),
    );
    final discountedTotal = (total - discount).clamp(0, double.infinity).toDouble();
    return _processCashCheckoutOnline(
      idempotencyKey: idempotencyKey,
      itemsJson: itemsJson,
      total: discountedTotal,
    );
  }

  Future<CheckoutIntent> createCheckoutIntent({
    required List<CartItem> items,
    required double discount,
  }) async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    final userId = _client.auth.currentUser?.id;

    if (businessId == null || branchId == null || userId == null) {
      throw Exception('Session not initialized. Please select a branch.');
    }

    final total = _computeTotal(items, discount);
    final idempotencyKey = _newIdempotencyKey();

    final response = await _client.rpc('create_checkout_intent', params: {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      'p_cashier_id': userId,
      'p_idempotency_key': idempotencyKey,
      'p_items': _buildItemsPayload(items),
      'p_total_amount': total,
      'p_method': 'card',
    });

    if (response.error != null) {
      throw Exception(response.error!.message);
    }

    final data = response.data as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('Empty intent response');
    }

    return CheckoutIntent(
      intentId: data['intent_id'] as String,
      cartId: data['cart_id'] as String,
      reference: data['reference'] as String,
    );
  }

  Future<PaystackInitResult> initiatePaystackCharge(String intentId) async {
    final response = await _client.functions.invoke(
      'paystack-initiate',
      body: {'intent_id': intentId},
    );

    final data = response.data as Map<String, dynamic>?;
    if (data == null || data['authorization_url'] == null) {
      final error = data?['error'] ?? 'Failed to initialize Paystack';
      throw Exception(error);
    }

    return PaystackInitResult(
      authorizationUrl: data['authorization_url'] as String,
      reference: data['reference'] as String,
      accessCode: data['access_code'] as String,
    );
  }

  Future<String?> checkPaymentStatus(String intentId) async {
    final response = await _client
        .from('payment_intents')
        .select('status')
        .eq('id', intentId)
        .single();

    final data = response as Map<String, dynamic>?;
    return data?['status'] as String?;
  }
}

class CheckoutIntent {
  final String intentId;
  final String cartId;
  final String reference;

  CheckoutIntent({
    required this.intentId,
    required this.cartId,
    required this.reference,
  });
}

class PaystackInitResult {
  final String authorizationUrl;
  final String reference;
  final String accessCode;

  PaystackInitResult({
    required this.authorizationUrl,
    required this.reference,
    required this.accessCode,
  });
}
