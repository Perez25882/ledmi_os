part of 'billing_bloc.dart';

enum PaymentMethod { cash, momo, card }

enum MoMoProvider { mtn, vodafone, airteltigo }

/// A single allocation within a split payment (POS-3). Each entry pairs a
/// payment method with the amount the cashier assigned to it.
class SplitPayment extends Equatable {
  final PaymentMethod method;
  final double amount;

  const SplitPayment({required this.method, this.amount = 0});

  SplitPayment copyWith({PaymentMethod? method, double? amount}) {
    return SplitPayment(
      method: method ?? this.method,
      amount: amount ?? this.amount,
    );
  }

  @override
  List<Object> get props => [method, amount];
}

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

  /// Split-payment allocations (POS-3). Empty by default so the single-payment
  /// flow is preserved; populated only when the cashier adds a second method.
  final List<SplitPayment> splitPayments;

  /// True when the last successful checkout was queued offline (no saleId yet).
  final bool wasQueued;

  /// The barcode that was scanned but not found in the catalog. The UI listens
  /// for this to surface the Quick Sale dialog. Cleared via
  /// [ClearQuickSalePromptEvent] once the dialog is dismissed.
  final String? notFoundBarcode;

  /// Smart Quick Sale suggestions — quick sale items sold frequently enough to
  /// warrant being promoted to the catalog. Empty by default; populated by
  /// [LoadQuickSaleSuggestionsEvent].
  final List<QuickSaleSuggestion> quickSaleSuggestions;

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
    this.splitPayments = const [],
    this.wasQueued = false,
    this.notFoundBarcode,
    this.quickSaleSuggestions = const [],
  });

  double get subtotal => cartItems.fold(0, (sum, item) => sum + item.total);

  double get totalAmount => (subtotal - discountAmount).clamp(0, double.infinity).toDouble();

  double get change => (amountTendered - totalAmount).clamp(0, double.infinity).toDouble();

  /// Sum of all split-payment allocations.
  double get splitTotal =>
      splitPayments.fold(0, (sum, entry) => sum + entry.amount);

  /// Outstanding amount still to be allocated across split payments.
  double get remainingBalance =>
      (totalAmount - splitTotal).clamp(0, double.infinity).toDouble();

  /// True when the cashier is combining more than one payment method.
  bool get isSplitPayment => splitPayments.length > 1;

  /// True when split allocations exactly cover the total (POS-3 validation).
  bool get splitBalanced =>
      splitPayments.isNotEmpty &&
      (totalAmount - splitTotal).abs() < 0.005;

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
    List<SplitPayment>? splitPayments,
    bool clearSplitPayments = false,
    bool? wasQueued,
    String? notFoundBarcode,
    bool clearNotFound = false,
    List<QuickSaleSuggestion>? quickSaleSuggestions,
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
      splitPayments:
          clearSplitPayments ? const [] : (splitPayments ?? this.splitPayments),
      wasQueued: wasQueued ?? this.wasQueued,
      notFoundBarcode:
          clearNotFound ? null : (notFoundBarcode ?? this.notFoundBarcode),
      quickSaleSuggestions:
          quickSaleSuggestions ?? this.quickSaleSuggestions,
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
        splitPayments,
        wasQueued,
        notFoundBarcode,
        quickSaleSuggestions,
      ];
}
