import 'package:equatable/equatable.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';

class CartItem extends Equatable {
  final Product product;
  final int quantity;
  final double discount; // line-level discount amount (absolute GHS)

  /// True when this line was added via the Quick Sale flow (scanned barcode
  /// not in the catalog). The [product] reference is a dummy placeholder; the
  /// human-readable label lives in [quickSaleName].
  final bool isQuickSale;

  /// Display name for quick-sale line items. Null for catalog items.
  final String? quickSaleName;

  const CartItem({
    required this.product,
    this.quantity = 1,
    this.discount = 0,
    this.isQuickSale = false,
    this.quickSaleName,
  });

  /// Human-readable label: the quick-sale name when applicable, otherwise the
  /// catalog product name.
  String get displayName =>
      isQuickSale ? (quickSaleName ?? product.name) : product.name;

  double get total => (product.price * quantity - discount)
      .clamp(0, double.infinity)
      .toDouble();

  bool get hasDiscount => discount > 0;

  CartItem copyWith({
    Product? product,
    int? quantity,
    double? discount,
    bool? isQuickSale,
    String? quickSaleName,
  }) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      discount: discount ?? this.discount,
      isQuickSale: isQuickSale ?? this.isQuickSale,
      quickSaleName: quickSaleName ?? this.quickSaleName,
    );
  }

  @override
  List<Object?> get props => [product, quantity, discount, isQuickSale, quickSaleName];
}
