import 'package:flutter_test/flutter_test.dart';

import 'package:billing_app/features/billing/domain/entities/cart_item.dart';
import 'package:billing_app/features/billing/presentation/bloc/billing_bloc.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';

Product _product({double price = 10.0, String id = 'p1'}) => Product(
      id: id,
      name: 'Product $id',
      barcode: 'BC-$id',
      price: price,
    );

BillingState _stateWith({
  List<CartItem> cartItems = const [],
  double discountAmount = 0,
  double amountTendered = 0,
  List<SplitPayment> splitPayments = const [],
}) =>
    BillingState(
      cartItems: cartItems,
      discountAmount: discountAmount,
      amountTendered: amountTendered,
      splitPayments: splitPayments,
    );

void main() {
  group('CartItem.total', () {
    test('multiplies unit price by quantity', () {
      final item = CartItem(product: _product(price: 12.50), quantity: 3);

      expect(item.total, 37.50);
    });

    test('subtracts the line-level discount', () {
      final item =
          CartItem(product: _product(price: 20), quantity: 2, discount: 5);

      expect(item.total, 35);
    });

    test('never returns a negative line total when the discount exceeds it', () {
      final item =
          CartItem(product: _product(price: 10), quantity: 1, discount: 25);

      expect(item.total, 0);
    });
  });

  group('CartItem.displayName', () {
    test('uses the catalog product name for normal lines', () {
      final item = CartItem(product: _product(id: 'abc'));

      expect(item.displayName, 'Product abc');
    });

    test('uses the quick-sale label for quick-sale lines', () {
      final item = CartItem(
        product: _product(),
        isQuickSale: true,
        quickSaleName: 'Loose sachet water',
      );

      expect(item.displayName, 'Loose sachet water');
    });

    test('falls back to the product name when a quick-sale line has no label',
        () {
      final item = CartItem(product: _product(id: 'xyz'), isQuickSale: true);

      expect(item.displayName, 'Product xyz');
    });
  });

  group('BillingState money math', () {
    test('subtotal sums every line total', () {
      final state = _stateWith(cartItems: [
        CartItem(product: _product(price: 10), quantity: 2),
        CartItem(product: _product(price: 4.25, id: 'p2'), quantity: 4),
      ]);

      expect(state.subtotal, 37);
    });

    test('totalAmount applies the cart-level discount to the subtotal', () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 50), quantity: 2)],
        discountAmount: 15,
      );

      expect(state.totalAmount, 85);
    });

    test('totalAmount never goes negative when the discount exceeds the cart',
        () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 10))],
        discountAmount: 40,
      );

      expect(state.totalAmount, 0);
    });

    test('change is what is owed back once tendered covers the total', () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 30))],
        amountTendered: 50,
      );

      expect(state.change, 20);
    });

    test('change is zero when the cashier is still short', () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 30))],
        amountTendered: 10,
      );

      expect(state.change, 0);
    });

    test('an empty cart totals zero', () {
      expect(_stateWith().subtotal, 0);
      expect(_stateWith().totalAmount, 0);
    });
  });

  group('BillingState split payments', () {
    test('splitTotal sums every allocation', () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 100))],
        splitPayments: const [
          SplitPayment(method: PaymentMethod.cash, amount: 60),
          SplitPayment(method: PaymentMethod.momo, amount: 40),
        ],
      );

      expect(state.splitTotal, 100);
    });

    test('remainingBalance reports what is still unallocated', () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 100))],
        splitPayments: const [
          SplitPayment(method: PaymentMethod.cash, amount: 30),
        ],
      );

      expect(state.remainingBalance, 70);
    });

    test('remainingBalance clamps to zero when over-allocated', () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 50))],
        splitPayments: const [
          SplitPayment(method: PaymentMethod.cash, amount: 80),
        ],
      );

      expect(state.remainingBalance, 0);
    });

    test('isSplitPayment only once a second method is added', () {
      final single = _stateWith(splitPayments: const [
        SplitPayment(method: PaymentMethod.cash, amount: 10),
      ]);
      final double_ = _stateWith(splitPayments: const [
        SplitPayment(method: PaymentMethod.cash, amount: 5),
        SplitPayment(method: PaymentMethod.card, amount: 5),
      ]);

      expect(single.isSplitPayment, isFalse);
      expect(double_.isSplitPayment, isTrue);
    });

    test('splitBalanced is true when allocations cover the total', () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 75))],
        splitPayments: const [
          SplitPayment(method: PaymentMethod.cash, amount: 25),
          SplitPayment(method: PaymentMethod.momo, amount: 50),
        ],
      );

      expect(state.splitBalanced, isTrue);
    });

    test('splitBalanced tolerates sub-pesewa floating point drift', () {
      final state = _stateWith(
        cartItems: [
          CartItem(product: _product(price: 0.1), quantity: 3),
        ],
        splitPayments: const [
          SplitPayment(method: PaymentMethod.cash, amount: 0.3),
        ],
      );

      // 0.1 * 3 is 0.30000000000000004 in IEEE-754; the balance check must not
      // reject a payment that is correct to the pesewa.
      expect(state.splitBalanced, isTrue);
    });

    test('splitBalanced is false when allocations fall short', () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 100))],
        splitPayments: const [
          SplitPayment(method: PaymentMethod.cash, amount: 99),
        ],
      );

      expect(state.splitBalanced, isFalse);
    });

    test('splitBalanced is false with no allocations at all', () {
      final state = _stateWith(
        cartItems: [CartItem(product: _product(price: 100))],
      );

      expect(state.splitBalanced, isFalse);
    });
  });
}
