part of 'owner_bloc.dart';

class TodaySummary extends Equatable {
  final double revenue;
  final int transactionCount;
  final double avgBasketValue;
  final Map<String, double> paymentBreakdown;

  const TodaySummary({
    required this.revenue,
    required this.transactionCount,
    required this.avgBasketValue,
    required this.paymentBreakdown,
  });

  @override
  List<Object?> get props =>
      [revenue, transactionCount, avgBasketValue, paymentBreakdown];
}

class LowStockItem extends Equatable {
  final String productId;
  final String name;
  final String barcode;
  final int currentStock;
  final int reorderLevel;
  final int suggestedReorderQty;

  const LowStockItem({
    required this.productId,
    required this.name,
    required this.barcode,
    required this.currentStock,
    required this.reorderLevel,
    required this.suggestedReorderQty,
  });

  @override
  List<Object?> get props => [
        productId,
        name,
        barcode,
        currentStock,
        reorderLevel,
        suggestedReorderQty,
      ];
}

class StockInLogEntry extends Equatable {
  final String productName;
  final int quantity;
  final String reason;
  final DateTime createdAt;

  const StockInLogEntry({
    required this.productName,
    required this.quantity,
    required this.reason,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [productName, quantity, reason, createdAt];
}

class WeeklyReport extends Equatable {
  final List<DailyRevenue> dailyRevenue;
  final List<TopProduct> topProducts;
  final Map<String, double> paymentBreakdown;

  const WeeklyReport({
    required this.dailyRevenue,
    required this.topProducts,
    required this.paymentBreakdown,
  });

  @override
  List<Object?> get props => [dailyRevenue, topProducts, paymentBreakdown];
}

class DailyRevenue extends Equatable {
  final DateTime date;
  final double revenue;
  final int transactionCount;

  const DailyRevenue({
    required this.date,
    required this.revenue,
    required this.transactionCount,
  });

  @override
  List<Object?> get props => [date, revenue, transactionCount];
}

class TopProduct extends Equatable {
  final String name;
  final int unitsSold;
  final double revenue;

  const TopProduct({
    required this.name,
    required this.unitsSold,
    required this.revenue,
  });

  @override
  List<Object?> get props => [name, unitsSold, revenue];
}

class OwnerState extends Equatable {
  final bool isLoading;
  final TodaySummary? todaySummary;
  final List<LowStockItem> lowStockItems;
  final List<StockPrediction> stockPredictions;
  final List<StockInLogEntry> stockInLog;
  final WeeklyReport? weeklyReport;
  final String? successMessage;
  final String? error;

  const OwnerState({
    this.isLoading = false,
    this.todaySummary,
    this.lowStockItems = const [],
    this.stockPredictions = const [],
    this.stockInLog = const [],
    this.weeklyReport,
    this.successMessage,
    this.error,
  });

  OwnerState copyWith({
    bool? isLoading,
    TodaySummary? todaySummary,
    List<LowStockItem>? lowStockItems,
    List<StockPrediction>? stockPredictions,
    List<StockInLogEntry>? stockInLog,
    WeeklyReport? weeklyReport,
    String? successMessage,
    String? error,
  }) {
    return OwnerState(
      isLoading: isLoading ?? this.isLoading,
      todaySummary: todaySummary ?? this.todaySummary,
      lowStockItems: lowStockItems ?? this.lowStockItems,
      stockPredictions: stockPredictions ?? this.stockPredictions,
      stockInLog: stockInLog ?? this.stockInLog,
      weeklyReport: weeklyReport ?? this.weeklyReport,
      successMessage: successMessage,
      error: error,
    );
  }

  @override
  List<Object?> get props => [
        isLoading,
        todaySummary,
        lowStockItems,
        stockPredictions,
        stockInLog,
        weeklyReport,
        successMessage,
        error,
      ];
}
