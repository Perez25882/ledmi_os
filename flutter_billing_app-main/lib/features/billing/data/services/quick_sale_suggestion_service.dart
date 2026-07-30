import 'package:hive/hive.dart';

import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../domain/entities/quick_sale_suggestion.dart';

/// Discovers quick sale items that have been sold frequently enough to warrant
/// being promoted into the product catalog.
///
/// The service queries Supabase for quick sale line items sold within the last
/// 7 days, groups them by name, and keeps only those sold at least
/// [minTimesSold] times. Dismissed suggestions are tracked in a local Hive box:
///
/// * "Later" dismissals are keyed by `later:<name>:<yyyy-MM-dd>` so the banner
///   resurfaces the next day.
/// * "Never" dismissals are keyed by `never:<name>` and suppress the suggestion
///   permanently.
class QuickSaleSuggestionService {
  static const String _boxName = 'quick_sale_suggestions';
  static const int minTimesSold = 3;
  static const Duration lookback = Duration(days: 7);

  final _client = SupabaseClientManager.client;

  Future<Box<String>> _openBox() => Hive.openBox<String>(_boxName);

  /// Returns the list of quick sale suggestions that should be surfaced to the
  /// cashier right now (after filtering out dismissed items).
  Future<List<QuickSaleSuggestion>> getSuggestions() async {
    final businessId = SessionManager.businessId;
    if (businessId == null) return [];

    final since = DateTime.now().subtract(lookback).toUtc().toIso8601String();

    final List<dynamic> rows;
    try {
      rows = await _client
          .from('sale_items')
          .select('quick_sale_name, unit_price')
          .eq('is_quick_sale', true)
          .eq('business_id', businessId)
          .not('quick_sale_name', 'is', null)
          .gte('created_at', since);
    } on Exception {
      return [];
    }

    // Group by name in Dart so we avoid relying on Postgres-specific aggregate
    // syntax and stay resilient to offline/edge cases.
    final Map<String, _Agg> aggregates = {};
    for (final row in rows) {
      final name = (row['quick_sale_name'] as String?)?.trim();
      if (name == null || name.isEmpty) continue;
      final price = (row['unit_price'] as num?)?.toDouble() ?? 0;
      final agg = aggregates[name] ?? _Agg();
      agg.count++;
      agg.priceSum += price;
    }

    final box = await _openBox();
    final today = _todayKey();

    final suggestions = <QuickSaleSuggestion>[];
    aggregates.forEach((name, agg) {
      if (agg.count < minTimesSold) return;
      // "Never" denylist — permanent.
      if (box.get('never:$name') != null) return;
      // "Later" — dismissed for today only.
      if (box.get('later:$name:$today') != null) return;
      suggestions.add(QuickSaleSuggestion(
        name: name,
        timesSold: agg.count,
        avgPrice: agg.priceSum / agg.count,
      ));
    });

    suggestions.sort((a, b) => b.timesSold.compareTo(a.timesSold));
    return suggestions;
  }

  /// Records a dismissal. When [permanent] is true the suggestion is denylisted
  /// forever ("Never"); otherwise it is suppressed only for today ("Later").
  Future<void> dismiss(String name, {required bool permanent}) async {
    final box = await _openBox();
    if (permanent) {
      await box.put('never:$name', '1');
    } else {
      await box.put('later:$name:${_todayKey()}', '1');
    }
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

class _Agg {
  int count = 0;
  double priceSum = 0;
}
