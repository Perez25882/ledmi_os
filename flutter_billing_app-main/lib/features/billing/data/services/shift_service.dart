import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';

class ShiftSummary {
  final int saleCount;
  final double cashTotal;
  final double otherTotal;

  ShiftSummary({
    required this.saleCount,
    required this.cashTotal,
    required this.otherTotal,
  });

  double get total => cashTotal + otherTotal;
}

class ShiftService {
  final _client = SupabaseClientManager.client;

  Future<String> openShift(double openingFloat) async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    final userId = _client.auth.currentUser?.id;

    if (businessId == null || branchId == null || userId == null) {
      throw Exception('Session not initialized');
    }

    final response = await _client.rpc('open_shift', params: {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      'p_cashier_id': userId,
      'p_opening_float': openingFloat,
    });

    if (response.error != null) {
      throw Exception(response.error!.message);
    }

    return response.data as String;
  }

  Future<void> closeShift({
    required String shiftId,
    required double actualCash,
    String? notes,
  }) async {
    final response = await _client.rpc('close_shift', params: {
      'p_shift_id': shiftId,
      'p_actual_cash': actualCash,
      'p_notes': notes,
    });

    if (response.error != null) {
      throw Exception(response.error!.message);
    }
  }

  Future<ShiftSummary> getShiftSummary() async {
    final openedAt = SessionManager.shiftOpenedAt;
    final userId = _client.auth.currentUser?.id;

    if (openedAt == null || userId == null) {
      return ShiftSummary(saleCount: 0, cashTotal: 0, otherTotal: 0);
    }

    final response = await _client
        .from('sales')
        .select('payment_id, payments(method, amount)')
        .eq('cashier_id', userId)
        .gte('created_at', openedAt.toIso8601String());

    final data = response as List<dynamic>? ?? [];
    int count = 0;
    double cash = 0;
    double other = 0;

    for (final row in data) {
      final payment = row['payments'] as Map<String, dynamic>?;
      if (payment == null) continue;
      final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
      final method = payment['method'] as String? ?? '';
      count++;
      if (method == 'cash') {
        cash += amount;
      } else {
        other += amount;
      }
    }

    return ShiftSummary(saleCount: count, cashTotal: cash, otherTotal: other);
  }
}
