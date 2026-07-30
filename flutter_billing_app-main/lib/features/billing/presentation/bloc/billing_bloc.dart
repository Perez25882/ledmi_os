import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/cart_item.dart';
import 'package:billing_app/features/product/domain/entities/product.dart';
import 'package:billing_app/features/product/domain/usecases/product_usecases.dart';
import '../../../../core/utils/printer_helper.dart';
import '../../../../core/data/hive_database.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../data/services/checkout_service.dart';
import '../../data/services/quick_sale_suggestion_service.dart';
import '../../domain/entities/quick_sale_suggestion.dart';
import '../../../../core/supabase/supabase_client.dart';

part 'billing_event.dart';
part 'billing_state.dart';

class BillingBloc extends Bloc<BillingEvent, BillingState> {
  final GetProductByBarcodeUseCase getProductByBarcodeUseCase;
  final CheckoutService checkoutService;
  final QuickSaleSuggestionService _suggestionService;
  final _client = SupabaseClientManager.client;

  BillingBloc({
    required this.getProductByBarcodeUseCase,
    required this.checkoutService,
    QuickSaleSuggestionService? suggestionService,
  })  : _suggestionService = suggestionService ?? QuickSaleSuggestionService(),
        super(const BillingState()) {
    on<ScanBarcodeEvent>(_onScanBarcode);
    on<AddProductToCartEvent>(_onAddProductToCart);
    on<RemoveProductFromCartEvent>(_onRemoveProductFromCart);
    on<UpdateQuantityEvent>(_onUpdateQuantity);
    on<ClearCartEvent>(_onClearCart);
    on<PrintReceiptEvent>(_onPrintReceipt);
    on<SetPaymentMethodEvent>(_onSetPaymentMethod);
    on<ApplyDiscountEvent>(_onApplyDiscount);
    on<SetItemDiscountEvent>(_onSetItemDiscount);
    on<SetAmountTenderedEvent>(_onSetAmountTendered);
    on<ProcessCashCheckoutEvent>(_onProcessCashCheckout);
    on<CreatePaymentIntentEvent>(_onCreatePaymentIntent);
    on<CardScannedEvent>(_onCardScanned);
    on<MoMoProviderSelectedEvent>(_onMoMoProviderSelected);
    on<MoMoPhoneEnteredEvent>(_onMoMoPhoneEntered);
    on<RequestMoMoCheckoutEvent>(_onRequestMoMoCheckout);
    on<MoMoChargePolledEvent>(_onMoMoChargePolled);
    on<CheckPaymentStatusEvent>(_onCheckPaymentStatus);
    on<CompleteCheckoutEvent>(_onCompleteCheckout);
    on<ResetCheckoutEvent>(_onResetCheckout);
    on<AddSplitPaymentEvent>(_onAddSplitPayment);
    on<RemoveSplitPaymentEvent>(_onRemoveSplitPayment);
    on<UpdateSplitPaymentAmountEvent>(_onUpdateSplitPaymentAmount);
    on<UpdateSplitPaymentMethodEvent>(_onUpdateSplitPaymentMethod);
    on<ClearSplitPaymentsEvent>(_onClearSplitPayments);
    on<ProcessSplitCheckoutEvent>(_onProcessSplitCheckout);
    on<AddQuickSaleEvent>(_onAddQuickSale);
    on<ClearQuickSalePromptEvent>(_onClearQuickSalePrompt);
    on<LoadQuickSaleSuggestionsEvent>(_onLoadQuickSaleSuggestions);
    on<DismissQuickSaleSuggestionEvent>(_onDismissQuickSaleSuggestion);
    on<AddQuickSaleToCatalogEvent>(_onAddQuickSaleToCatalog);
  }

  Future<void> _onScanBarcode(
      ScanBarcodeEvent event, Emitter<BillingState> emit) async {
    final result = await getProductByBarcodeUseCase(event.barcode);
    result.fold(
      (failure) => emit(state.copyWith(
          notFoundBarcode: event.barcode, clearError: true)),
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

  void _onSetItemDiscount(
      SetItemDiscountEvent event, Emitter<BillingState> emit) {
    final index = state.cartItems
        .indexWhere((item) => item.product.id == event.productId);
    if (index < 0) return;

    final maxDiscount = state.cartItems[index].product.price *
        state.cartItems[index].quantity;
    final clamped =
        event.discountAmount.clamp(0, maxDiscount).toDouble();

    final items = List<CartItem>.from(state.cartItems);
    items[index] = items[index].copyWith(discount: clamped);
    emit(state.copyWith(cartItems: items, error: null));
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

      // PRD §11: hand off to the receipt preview page instead of auto-printing
      // and clearing here. The UI listener captures the sale data and
      // navigates; printing is triggered from the receipt preview.
      emit(state.copyWith(
        isProcessing: false,
        saleId: result.saleId,
        wasQueued: result.wasQueued,
        checkoutSuccess: true,
      ));
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
        method: event.method,
      );
      final init = await checkoutService.initiatePaystackCharge(
        intent.intentId,
        momoProviderCode: _momoProviderCode(state.momoProvider),
        momoPhone: state.momoPhone,
      );

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

  void _onCardScanned(
      CardScannedEvent event, Emitter<BillingState> emit) {
    emit(state.copyWith(
      cardLast4: event.last4,
      cardExpiry: event.expiry,
      error: null,
    ));
  }

  void _onMoMoProviderSelected(
      MoMoProviderSelectedEvent event, Emitter<BillingState> emit) {
    emit(state.copyWith(momoProvider: event.provider, error: null));
  }

  void _onMoMoPhoneEntered(
      MoMoPhoneEnteredEvent event, Emitter<BillingState> emit) {
    emit(state.copyWith(momoPhone: event.phone, error: null));
  }

  Future<void> _onRequestMoMoCheckout(
      RequestMoMoCheckoutEvent event, Emitter<BillingState> emit) async {
    if (state.momoProvider == null) {
      emit(state.copyWith(error: 'Select a MoMo provider'));
      return;
    }
    if (state.momoPhone == null || state.momoPhone!.trim().isEmpty) {
      emit(state.copyWith(error: 'Enter customer MoMo phone number'));
      return;
    }
    add(const CreatePaymentIntentEvent(method: 'momo'));
  }

  Future<void> _onMoMoChargePolled(
      MoMoChargePolledEvent event, Emitter<BillingState> emit) async {
    add(CheckPaymentStatusEvent(event.intentId));
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
          saleId: event.intentId,
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
    // PRD §11: mark the sale complete and let the receipt preview handle
    // printing. The cart is preserved until the UI resets after navigation.
    emit(state.copyWith(
      saleId: event.saleId,
      checkoutSuccess: true,
      paymentStatus: 'completed',
    ));
  }

  Future<void> _onResetCheckout(
      ResetCheckoutEvent event, Emitter<BillingState> emit) async {
    emit(state.cleared());
  }

  // --- Split payments (POS-3) ---

  void _onAddSplitPayment(
      AddSplitPaymentEvent event, Emitter<BillingState> emit) {
    final list = List<SplitPayment>.from(state.splitPayments);
    // Entering split mode: seed the currently-selected single method as the
    // first allocation (carrying the full total) so the cashier can carve it
    // up across the additional methods.
    if (list.isEmpty) {
      list.add(SplitPayment(
          method: state.paymentMethod, amount: state.totalAmount));
    }
    list.add(SplitPayment(method: event.method, amount: 0));
    emit(state.copyWith(splitPayments: list, error: null));
  }

  void _onRemoveSplitPayment(
      RemoveSplitPaymentEvent event, Emitter<BillingState> emit) {
    final list = List<SplitPayment>.from(state.splitPayments);
    if (event.index >= 0 && event.index < list.length) {
      list.removeAt(event.index);
    }
    emit(state.copyWith(splitPayments: list, error: null));
  }

  void _onUpdateSplitPaymentAmount(
      UpdateSplitPaymentAmountEvent event, Emitter<BillingState> emit) {
    final list = List<SplitPayment>.from(state.splitPayments);
    if (event.index >= 0 && event.index < list.length) {
      list[event.index] = list[event.index].copyWith(
          amount: event.amount.clamp(0, double.infinity).toDouble());
    }
    emit(state.copyWith(splitPayments: list, error: null));
  }

  void _onUpdateSplitPaymentMethod(
      UpdateSplitPaymentMethodEvent event, Emitter<BillingState> emit) {
    final list = List<SplitPayment>.from(state.splitPayments);
    if (event.index >= 0 && event.index < list.length) {
      list[event.index] = list[event.index].copyWith(method: event.method);
    }
    emit(state.copyWith(splitPayments: list, error: null));
  }

  void _onClearSplitPayments(
      ClearSplitPaymentsEvent event, Emitter<BillingState> emit) {
    emit(state.copyWith(clearSplitPayments: true, error: null));
  }

  Future<void> _onProcessSplitCheckout(
      ProcessSplitCheckoutEvent event, Emitter<BillingState> emit) async {
    if (state.cartItems.isEmpty) {
      emit(state.copyWith(error: 'Cart is empty'));
      return;
    }
    if (!SessionManager.isShiftOpen) {
      emit(state.copyWith(error: 'Open a shift before checking out'));
      return;
    }
    if (!state.splitBalanced) {
      emit(state.copyWith(
          error:
              'Allocated amounts (GHS ${state.splitTotal.toStringAsFixed(2)}) '
              'must equal the total (GHS ${state.totalAmount.toStringAsFixed(2)})'));
      return;
    }

    emit(state.copyWith(isProcessing: true, error: null));

    try {
      final result = await checkoutService.processSplitCheckout(
        items: state.cartItems,
        discount: state.discountAmount,
        payments: state.splitPayments
            .map((p) =>
                SplitPaymentInput(method: _methodCode(p.method), amount: p.amount))
            .toList(),
      );

      // PRD §11: hand off to the receipt preview page.
      emit(state.copyWith(
        isProcessing: false,
        saleId: result.saleId,
        wasQueued: result.wasQueued,
        checkoutSuccess: true,
      ));
    } on Exception catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  String? _momoProviderCode(MoMoProvider? provider) {
    switch (provider) {
      case MoMoProvider.mtn:
        return 'mtn';
      case MoMoProvider.vodafone:
        return 'vod';
      case MoMoProvider.airteltigo:
        return 'atl';
      case null:
        return null;
    }
  }

  // --- Quick Sale (scanned barcode not in catalog) ---

  void _onAddQuickSale(
      AddQuickSaleEvent event, Emitter<BillingState> emit) {
    final cleanState = state.copyWith(clearNotFound: true, clearError: true);

    final dummyProduct = Product(
      id: const Uuid().v4(),
      name: event.name,
      barcode: '',
      price: event.price,
    );

    final newItem = CartItem(
      product: dummyProduct,
      quantity: event.quantity,
      isQuickSale: true,
      quickSaleName: event.name,
    );

    emit(cleanState.copyWith(
        cartItems: [...cleanState.cartItems, newItem], error: null));
  }

  void _onClearQuickSalePrompt(
      ClearQuickSalePromptEvent event, Emitter<BillingState> emit) {
    emit(state.copyWith(clearNotFound: true));
  }

  // --- Smart Quick Sale Suggestions ---

  Future<void> _onLoadQuickSaleSuggestions(
      LoadQuickSaleSuggestionsEvent event, Emitter<BillingState> emit) async {
    final suggestions = await _suggestionService.getSuggestions();
    emit(state.copyWith(quickSaleSuggestions: suggestions, clearError: true));
  }

  Future<void> _onDismissQuickSaleSuggestion(
      DismissQuickSaleSuggestionEvent event,
      Emitter<BillingState> emit) async {
    await _suggestionService.dismiss(event.name, permanent: event.permanent);
    final remaining = state.quickSaleSuggestions
        .where((s) => s.name != event.name)
        .toList();
    emit(state.copyWith(quickSaleSuggestions: remaining));
  }

  Future<void> _onAddQuickSaleToCatalog(
      AddQuickSaleToCatalogEvent event, Emitter<BillingState> emit) async {
    emit(state.copyWith(isProcessing: true, clearError: true));

    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    if (businessId == null || branchId == null) {
      emit(state.copyWith(
          isProcessing: false, error: 'Session not initialized'));
      return;
    }

    try {
      final productId = const Uuid().v4();
      await _client.from('products').insert({
        'id': productId,
        'business_id': businessId,
        'name': event.name,
        'barcode': '',
        'selling_price': event.price,
        if (event.category.isNotEmpty) 'category': event.category,
      });

      await _client.from('inventory').insert({
        'product_id': productId,
        'branch_id': branchId,
        'quantity': 0,
      });

      // Denylist permanently so we don't re-suggest a promoted item.
      await _suggestionService.dismiss(event.name, permanent: true);

      final remaining = state.quickSaleSuggestions
          .where((s) => s.name != event.name)
          .toList();

      emit(state.copyWith(
        isProcessing: false,
        quickSaleSuggestions: remaining,
        error: '"${event.name}" added to catalog',
      ));
    } on Exception catch (e) {
      emit(state.copyWith(isProcessing: false, error: e.toString()));
    }
  }

  String _methodCode(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.momo:
        return 'momo';
      case PaymentMethod.card:
        return 'card';
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
                'name': item.displayName,
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
