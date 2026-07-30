part of 'owner_bloc.dart';

abstract class OwnerEvent extends Equatable {
  const OwnerEvent();
  @override
  List<Object?> get props => [];
}

class LoadTodaySummary extends OwnerEvent {}

class LoadLowStock extends OwnerEvent {}

class LoadStockPredictions extends OwnerEvent {}

class DismissStockAlert extends OwnerEvent {
  final String productId;
  final String productName;

  const DismissStockAlert({
    required this.productId,
    required this.productName,
  });

  @override
  List<Object?> get props => [productId, productName];
}

class LoadStockInLog extends OwnerEvent {}

class RecordStockIn extends OwnerEvent {
  final String productId;
  final int quantity;
  final double? costPrice;

  const RecordStockIn({
    required this.productId,
    required this.quantity,
    this.costPrice,
  });

  @override
  List<Object?> get props => [productId, quantity, costPrice];
}

class QuickAddProduct extends OwnerEvent {
  final String barcode;
  final String name;
  final double price;
  final String? category;
  final int stockQty;
  final double? costPrice;

  const QuickAddProduct({
    required this.barcode,
    required this.name,
    required this.price,
    this.category,
    required this.stockQty,
    this.costPrice,
  });

  @override
  List<Object?> get props => [barcode, name, price, category, stockQty, costPrice];
}

class LoadWeeklyReport extends OwnerEvent {}

class MarkLowStockOrdered extends OwnerEvent {
  final String productId;
  final String productName;
  final int reorderQty;

  const MarkLowStockOrdered({
    required this.productId,
    required this.productName,
    required this.reorderQty,
  });

  @override
  List<Object?> get props => [productId, productName, reorderQty];
}
