import 'package:equatable/equatable.dart';

/// Urgency bucket for a low-stock prediction.
///
/// - [critical]: stockout predicted within ~1 day.
/// - [warning]: stockout predicted within ~3 days.
/// - [info]: stockout predicted within ~7 days (or velocity unknown).
enum PredictionUrgency { critical, warning, info }

/// AI-powered low-stock prediction for a single product.
///
/// Combines raw inventory data with sales-velocity calculations and an
/// optional one-line AI insight produced by Ledmi (NVIDIA NIM).
class StockPrediction extends Equatable {
  final String productId;
  final String name;
  final int currentStock;
  final double dailyVelocity;
  final double? daysUntilStockout;
  final int suggestedReorder;
  final PredictionUrgency urgency;
  final int? lastSoldHoursAgo;
  final String? aiInsight;

  const StockPrediction({
    required this.productId,
    required this.name,
    required this.currentStock,
    required this.dailyVelocity,
    required this.daysUntilStockout,
    required this.suggestedReorder,
    required this.urgency,
    this.lastSoldHoursAgo,
    this.aiInsight,
  });

  factory StockPrediction.fromJson(Map<String, dynamic> json) {
    final days = (json['days_until_stockout'] as num?)?.toDouble();
    return StockPrediction(
      productId: json['product_id'] as String,
      name: json['name'] as String? ?? 'Unknown',
      currentStock: (json['current_stock'] as num?)?.toInt() ?? 0,
      dailyVelocity:
          (json['daily_velocity'] as num?)?.toDouble() ?? 0.0,
      daysUntilStockout: days,
      suggestedReorder: (json['suggested_reorder'] as num?)?.toInt() ?? 0,
      urgency: _parseUrgency(json['urgency'] as String?),
      lastSoldHoursAgo: (json['last_sold_hours_ago'] as num?)?.toInt(),
      aiInsight: json['ai_insight'] as String?,
    );
  }

  static PredictionUrgency _parseUrgency(String? value) {
    switch (value) {
      case 'critical':
        return PredictionUrgency.critical;
      case 'warning':
        return PredictionUrgency.warning;
      default:
        return PredictionUrgency.info;
    }
  }

  /// Sort weight: critical first, then warning, then info.
  int get urgencyWeight {
    switch (urgency) {
      case PredictionUrgency.critical:
        return 0;
      case PredictionUrgency.warning:
        return 1;
      case PredictionUrgency.info:
        return 2;
    }
  }

  @override
  List<Object?> get props => [
        productId,
        name,
        currentStock,
        dailyVelocity,
        daysUntilStockout,
        suggestedReorder,
        urgency,
        lastSoldHoursAgo,
        aiInsight,
      ];
}
