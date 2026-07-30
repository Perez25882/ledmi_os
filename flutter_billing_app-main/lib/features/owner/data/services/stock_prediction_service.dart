import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/session_manager.dart';
import '../../domain/entities/stock_prediction.dart';

/// Fetches AI-powered low-stock predictions.
///
/// Primary path: calls the LedgerMind dashboard API route
/// `/api/ledmi/stock-predictions` which computes sales velocity and enriches
/// each item with a Ledmi insight via NVIDIA NIM.
///
/// Fallback path: if the API is unreachable (offline / auth mismatch), the
/// service computes the same velocity math locally against Supabase so the
/// POS still surfaces useful predictions without connectivity.
class StockPredictionService {
  final SupabaseClient _client;
  final http.Client _httpClient;

  StockPredictionService({
    SupabaseClient? client,
    http.Client? httpClient,
  })  : _client = client ?? Supabase.instance.client,
        _httpClient = httpClient ?? http.Client();

  /// Returns a list of [StockPrediction] sorted by urgency (critical first).
  Future<List<StockPrediction>> fetchPredictions() async {
    try {
      final remote = await _fetchFromApi();
      if (remote != null) return remote;
    } catch (_) {
      // Network / auth error — fall through to local calculation.
    }
    return _computeLocally();
  }

  Future<List<StockPrediction>?> _fetchFromApi() async {
    final baseUrl = dotenv.env['DASHBOARD_API_URL'];
    if (baseUrl == null || baseUrl.isEmpty) return null;

    final uri = Uri.parse('$baseUrl/api/ledmi/stock-predictions');
    final session = _client.auth.currentSession;
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (session != null) 'Authorization': 'Bearer ${session.accessToken}',
    };

    final res = await _httpClient
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final list = (body['predictions'] as List?) ?? [];
    final predictions = list
        .map((e) => StockPrediction.fromJson(e as Map<String, dynamic>))
        .toList();
    predictions.sort(_comparePredictions);
    return predictions;
  }

  /// Local fallback: query inventory + last 7 days of sale_items directly
  /// from Supabase and compute velocity / stockout / reorder locally.
  Future<List<StockPrediction>> _computeLocally() async {
    final branchId = SessionManager.branchId;
    if (branchId == null) return [];

    final inventoryRows = await _client
        .from('inventory')
        .select('''
          quantity,
          product:products(id, name)
        ''')
        .eq('branch_id', branchId)
        .filter('quantity', 'lte', 'reorder_level');

    if (inventoryRows.isEmpty) return [];

    final since = DateTime.now().subtract(const Duration(days: 7));
    final sinceIso = since.toIso8601String();

    final predictions = <StockPrediction>[];
    for (final row in inventoryRows) {
      final product = row['product'] as Map<String, dynamic>?;
      if (product == null) continue;
      final productId = product['id'] as String;
      final name = (product['name'] as String?) ?? 'Unknown';
      final currentStock = (row['quantity'] as num?)?.toInt() ?? 0;

      final saleRows = await _client
          .from('sale_items')
          .select('quantity, sale:sales!inner(created_at)')
          .eq('product_id', productId)
          .eq('sale.branch_id', branchId)
          .gte('sale.created_at', sinceIso);

      int totalSold = 0;
      DateTime? lastSoldAt;
      for (final si in saleRows) {
        totalSold += (si['quantity'] as num?)?.toInt() ?? 0;
        final created = si['sale']?['created_at'] as String?;
        if (created != null) {
          final d = DateTime.tryParse(created);
          if (d != null && (lastSoldAt == null || d.isAfter(lastSoldAt))) {
            lastSoldAt = d;
          }
        }
      }

      final dailyVelocity = totalSold / 7;
      final daysUntilStockout =
          dailyVelocity > 0 ? currentStock / dailyVelocity : null;
      final suggestedReorder =
          dailyVelocity > 0 ? (dailyVelocity * 7).round().clamp(1, 9999) : 10;
      final urgency = _urgencyFor(daysUntilStockout);
      final lastSoldHoursAgo = lastSoldAt == null
          ? null
          : DateTime.now().difference(lastSoldAt).inHours;

      predictions.add(StockPrediction(
        productId: productId,
        name: name,
        currentStock: currentStock,
        dailyVelocity: double.parse(dailyVelocity.toStringAsFixed(2)),
        daysUntilStockout: daysUntilStockout == null
            ? null
            : double.parse(daysUntilStockout.toStringAsFixed(2)),
        suggestedReorder: suggestedReorder,
        urgency: urgency,
        lastSoldHoursAgo: lastSoldHoursAgo,
        aiInsight: null,
      ));
    }

    predictions.sort(_comparePredictions);
    return predictions;
  }

  PredictionUrgency _urgencyFor(double? daysUntilStockout) {
    if (daysUntilStockout == null) return PredictionUrgency.info;
    if (daysUntilStockout < 1) return PredictionUrgency.critical;
    if (daysUntilStockout < 3) return PredictionUrgency.warning;
    return PredictionUrgency.info;
  }

  int _comparePredictions(StockPrediction a, StockPrediction b) {
    final u = a.urgencyWeight.compareTo(b.urgencyWeight);
    if (u != 0) return u;
    final ad = a.daysUntilStockout ?? double.infinity;
    final bd = b.daysUntilStockout ?? double.infinity;
    return ad.compareTo(bd);
  }
}
