part of 'billing_bloc.dart';

enum PaymentMethod { cash, momo, card }

enum MoMoProvider { mtn, vodafone, airteltigo }

class BillingState extends Equatable {
  final List<CartItem> cartItems;
  final PaymentMethod paymentMethod;
  final double discountAmount;
  final double amountTendered;
  final String? paymentIntentId;
  final String? authorizationUrl;
  final String? paymentStatus;
  final String? saleId;
  final bool isProcessing;
  final bool checkoutSuccess;
  final String? error;
  final bool isPrinting;
  final bool printSuccess;
  final String? cardLast4;
  final String? cardExpiry;
  final MoMoProvider? momoProvider;
  final String? momoPhone;

  const BillingState({
    this.cartItems = const [],
    this.paymentMethod = PaymentMethod.cash,
    this.discountAmount = 0,
    this.amountTendered = 0,
    this.paymentIntentId,
    this.authorizationUrl,
    this.paymentStatus,
    this.saleId,
    this.isProcessing = false,
    this.checkoutSuccess = false,
    this.error,
    this.isPrinting = false,
    this.printSuccess = false,
    this.cardLast4,
    this.cardExpiry,
    this.momoProvider,
    this.momoPhone,
  });

  double get subtotal => cartItems.fold(0, (sum, item) => sum + item.total);

  double get totalAmount => (subtotal - discountAmount).clamp(0, double.infinity).toDouble();

  double get change => (amountTendered - totalAmount).clamp(0, double.infinity).toDouble();

  BillingState copyWith({
    List<CartItem>? cartItems,
    PaymentMethod? paymentMethod,
    double? discountAmount,
    double? amountTendered,
    String? paymentIntentId,
    String? authorizationUrl,
    String? paymentStatus,
    String? saleId,
    bool? isProcessing,
    bool? checkoutSuccess,
    String? error,
    bool clearError = false,
    bool? isPrinting,
    bool? printSuccess,
    String? cardLast4,
    String? cardExpiry,
    MoMoProvider? momoProvider,
    String? momoPhone,
  }) {
    return BillingState(
      cartItems: cartItems ?? this.cartItems,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      discountAmount: discountAmount ?? this.discountAmount,
      amountTendered: amountTendered ?? this.amountTendered,
      paymentIntentId: clearError ? null : (paymentIntentId ?? this.paymentIntentId),
      authorizationUrl: clearError ? null : (authorizationUrl ?? this.authorizationUrl),
      paymentStatus: clearError ? null : (paymentStatus ?? this.paymentStatus),
      saleId: saleId ?? this.saleId,
      isProcessing: isProcessing ?? this.isProcessing,
      checkoutSuccess: checkoutSuccess ?? this.checkoutSuccess,
      error: clearError ? null : (error ?? this.error),
      isPrinting: isPrinting ?? this.isPrinting,
      printSuccess: printSuccess ?? this.printSuccess,
      cardLast4: cardLast4 ?? this.cardLast4,
      cardExpiry: cardExpiry ?? this.cardExpiry,
      momoProvider: momoProvider ?? this.momoProvider,
      momoPhone: momoPhone ?? this.momoPhone,
    );
  }

  BillingState cleared() => const BillingState();

  @override
  List<Object?> get props => [
        cartItems,
        paymentMethod,
        discountAmount,
        amountTendered,
        paymentIntentId,
        authorizationUrl,
        paymentStatus,
        saleId,
        isProcessing,
        checkoutSuccess,
        error,
        isPrinting,
        printSuccess,
        cardLast4,
        cardExpiry,
        momoProvider,
        momoPhone,
      ];
}
