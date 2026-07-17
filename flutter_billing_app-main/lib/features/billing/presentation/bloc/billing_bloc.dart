import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../domain/entities/cart_item.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/product/domain/usecases/product_usecases.dart';
import '../../../../core/utils/printer_helper.dart';
import '../../../../core/data/hive_database.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../data/services/checkout_service.dart';

part 'billing_event.dart';
part 'billing_state.dart';

class BillingBloc extends Bloc<BillingEvent, BillingState> {
  final GetProductByBarcodeUseCase getProductByBarcodeUseCase;
  final CheckoutService checkoutService;

  BillingBloc({
    required this.getProductByBarcodeUseCase,
    required this.checkoutService,
  }) : super(const BillingState()) {
    on<ScanBarcodeEvent>(_onScanBarcode);
    on<AddProductToCartEvent>(_onAddProductToCart);
    on<RemoveProductFromCartEvent>(_onRemoveProductFromCart);
    on<UpdateQuantityEvent>(_onUpdateQuantity);
    on<ClearCartEvent>(_onClearCart);
    on<PrintReceiptEvent>(_onPrintReceipt);
    on<SetPaymentMethodEvent>(_onSetPaymentMethod);
    on<ApplyDiscountEvent>(_onApplyDiscount);
    on<SetAmountTenderedEvent>(_onSetAmountTendered);
    on<ProcessCashCheckoutEvent>(_onProcessCashCheckout);
    on<CreatePaymentIntentEvent>(_onCreatePaymentIntent);
    on<CheckPaymentStatusEvent>(_onCheckPaymentStatus);
    on<CompleteCheckoutEvent>(_onCompleteCheckout);
    on<ResetCheckoutEvent>(_onResetCheckout);
  }

  Future<void> _onScanBarcode(
      ScanBarcodeEvent event, Emitter<BillingState> emit) async {
    final result = await getProductByBarcodeUseCase(event.barcode);
    result.fold(
      (failure) =>
          emit(state.copyWith(error: 'Product not found: ${event.barcode}')),
      (product) => add(AddProductToCartEvent(product)),
    );
  }

  void _onAddProductToCart(
      AddProductToCartEvent event, Emitter<BillingState> emit) {
    final cleanState = state.copyWith(error: null);

    final existingIndex = cleanState.cartItems
        .indexWhere((item) => item.product.id == event.product.id);
    if (existingIndex >= 0) {
      final existingItem = cleanState.cartItems[existingIndex];
      final backendItems = List<CartItem>.from(cleanState.cartItems);
      backendItems[existingIndex] =
          existingItem.copyWith(quantity: existingItem.quantity + 1);
      emit(cleanState.copyWith(cartItems: backendItems, error: null));
    } else {
      final newItem = CartItem(product: event.product);
      emit(cleanState.copyWith(
          cartItems: [...cleanState.cartItems, newItem], error: null));
    }
  }

  void _onRemoveProductFromCart(
      RemoveProductFromCartEvent event, Emitter<BillingState> emit) {
    final updatedList = state.cartItems
        .where((item) => item.product.id != event.productId)
        .toList();
    emit(state.copyWith(cartItems: updatedList));
  }

  void _onUpdateQuantity(
      UpdateQuantityEvent event, Emitter<BillingState> emit) {
    if (event.quantity <= 0) {
      add(RemoveProductFromCartEvent(event.productId));
      return;
    }

    final index = state.cartItems
        .indexWhere((item) => item.product.id == event.productId);
    if (index >= 0) {
      final items = List<CartItem>.from(state.cartItems);
      items[index] = items[index].copyWith(quantity: event.quantity);
      emit(state.copyWith(cartItems: items));
    }
  }

  void _onClearCart(ClearCartEvent event, Emitter<BillingState> emit) {
    emit(state.cleared());
  }

  void _onSetPaymentMethod(
      SetPaymentMethodEvent event, Emitter<BillingState> emit) {
    emit(state.copyWith(
      paymentMethod: event.method,
      error: null,
      clearError: false,
    ));
  }

  void _onApplyDiscount(
      ApplyDiscountEvent event, Emitter<BillingState> emit) {
    emit(state.copyWith(
      discountAmount: event.amount.clamp(0, double.infinity).toDouble(),
      error: null,
    ));
  }

  void _onSetAmountTendered(
      SetAmountTenderedEvent event, Emitter<BillingState> emit) {
    emit(state.copyWith(
      amountTendered: event.amount.clamp(0, double.infinity).toDouble(),
      error: null,
    ));
  }

  Future<void> _onProcessCashCheckout(
      ProcessCashCheckoutEvent event, Emitter<BillingState> emit) async {
    if (state.cartItems.isEmpty) {
      emit(state.copyWith(error: 'Cart is empty'));
      return;
    }
    if (!SessionManager.isShiftOpen) {
      emit(state.copyWith(error: 'Open a shift before checking out'));
      return;
    }
    if (state.amountTendered < state.totalAmount) {
      emit(state.copyWith(error: 'Insufficient amount tendered'));
      return;
    }

    emit(state.copyWith(isProcessing: true, error: null));

    try {
      final result = await checkoutService.processCashCheckout(
        items: state.cartItems,
        discount: state.discountAmount,
      );

      emit(state.copyWith(
        isProcessing: false,
        saleId: result.saleId,
        checkoutSuccess: true,
      ));

      final shopName = await _loadShopName();
      await _printReceipt(
        shopName,
        emit,
        footer: result.wasQueued
            ? 'OFFLINE PENDING - will sync when online'
            : 'Thank you!',
      );

      emit(state.cleared());
    } on Exception catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  Future<void> _onCreatePaymentIntent(
      CreatePaymentIntentEvent event, Emitter<BillingState> emit) async {
    if (state.cartItems.isEmpty) {
      emit(state.copyWith(error: 'Cart is empty'));
      return;
    }
    if (!SessionManager.isShiftOpen) {
      emit(state.copyWith(error: 'Open a shift before checking out'));
      return;
    }

    emit(state.copyWith(isProcessing: true, error: null));

    try {
      final intent = await checkoutService.createCheckoutIntent(
        items: state.cartItems,
        discount: state.discountAmount,
      );
      final init = await checkoutService.initiatePaystackCharge(intent.intentId);

      emit(state.copyWith(
        isProcessing: false,
        paymentIntentId: intent.intentId,
        authorizationUrl: init.authorizationUrl,
        paymentStatus: 'pending',
      ));

      await launchUrl(
        Uri.parse(init.authorizationUrl),
        mode: LaunchMode.inAppWebView,
      );
    } on Exception catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  Future<void> _onCheckPaymentStatus(
      CheckPaymentStatusEvent event, Emitter<BillingState> emit) async {
    emit(state.copyWith(isProcessing: true, error: null));

    try {
      final status = await checkoutService.checkPaymentStatus(event.intentId);
      if (status == 'completed') {
        emit(state.copyWith(
          isProcessing: false,
          paymentStatus: status,
          checkoutSuccess: true,
        ));
        add(CompleteCheckoutEvent(event.intentId));
      } else {
        emit(state.copyWith(
          isProcessing: false,
          paymentStatus: status ?? 'pending',
        ));
      }
    } on Exception catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  Future<void> _onCompleteCheckout(
      CompleteCheckoutEvent event, Emitter<BillingState> emit) async {
    final shopName = await _loadShopName();
    await _printReceipt(shopName, emit, footer: 'Thank you!');
    emit(state.cleared());
  }

  Future<void> _onResetCheckout(
      ResetCheckoutEvent event, Emitter<BillingState> emit) async {
    emit(state.cleared());
  }

  Future<String> _loadShopName() async {
    final saved = HiveDatabase.settingsBox.get('shop_name');
    if (saved != null && saved.toString().isNotEmpty) {
      return saved.toString();
    }
    return 'LedgerMind Store';
  }

  Future<void> _printReceipt(
    String shopName,
    Emitter<BillingState> emit, {
    String footer = 'Thank you!',
  }) async {
    final printerHelper = PrinterHelper();

    if (!printerHelper.isConnected) {
      final savedMac = HiveDatabase.settingsBox.get('printer_mac');
      if (savedMac != null) {
        final connected = await printerHelper.connect(savedMac);
        if (!connected) {
          emit(state.copyWith(
              error: 'Failed to auto-connect to printer!', clearError: false));
          emit(state.copyWith(clearError: true));
          return;
        }
      } else {
        emit(state.copyWith(
            error: 'Printer not connected & no saved printer found!',
            clearError: false));
        emit(state.copyWith(clearError: true));
        return;
      }
    }

    emit(state.copyWith(
        isPrinting: true, printSuccess: false, clearError: true));

    try {
      final items = state.cartItems
          .map((item) => {
                'name': item.product.name,
                'qty': item.quantity,
                'price': item.product.price,
                'total': item.total,
              })
          .toList();

      await printerHelper.printReceipt(
          shopName: shopName,
          address1: '',
          address2: '',
          phone: '',
          items: items,
          total: state.totalAmount,
          footer: footer);

      emit(state.copyWith(isPrinting: false, printSuccess: true));
    } catch (e) {
      emit(state.copyWith(
          isPrinting: false, error: 'Print failed: $e', clearError: false));
      emit(state.copyWith(clearError: true));
    }
  }

  Future<void> _onPrintReceipt(
      PrintReceiptEvent event, Emitter<BillingState> emit) async {
    final printerHelper = PrinterHelper();

    if (!printerHelper.isConnected) {
      final savedMac = HiveDatabase.settingsBox.get('printer_mac');
      if (savedMac != null) {
        final connected = await printerHelper.connect(savedMac);
        if (!connected) {
          emit(state.copyWith(
              error: 'Failed to auto-connect to printer!', clearError: false));
          emit(state.copyWith(clearError: true));
          return;
        }
      } else {
        emit(state.copyWith(
            error: 'Printer not connected & no saved printer found!',
            clearError: false));
        emit(state.copyWith(clearError: true));
        return;
      }
    }

    emit(state.copyWith(
        isPrinting: true, printSuccess: false, clearError: true));

    try {
      final items = state.cartItems
          .map((item) => {
                'name': item.product.name,
                'qty': item.quantity,
                'price': item.product.price,
                'total': item.total,
              })
          .toList();

      await printerHelper.printReceipt(
          shopName: event.shopName,
          address1: event.address1,
          address2: event.address2,
          phone: event.phone,
          items: items,
          total: state.totalAmount,
          footer: event.footer);

      emit(state.copyWith(isPrinting: false, printSuccess: true));
    } catch (e) {
      emit(state.copyWith(
          isPrinting: false, error: 'Print failed: $e', clearError: false));
      emit(state.copyWith(clearError: true));
    }
  }
}
