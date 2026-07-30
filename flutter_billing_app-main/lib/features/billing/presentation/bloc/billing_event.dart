part of 'billing_bloc.dart';

abstract class BillingEvent extends Equatable {
  const BillingEvent();
  @override
  List<Object> get props => [];
}

class ScanBarcodeEvent extends BillingEvent {
  final String barcode;
  const ScanBarcodeEvent(this.barcode);
  @override
  List<Object> get props => [barcode];
}

class AddProductToCartEvent extends BillingEvent {
  final Product product;
  const AddProductToCartEvent(this.product);
  @override
  List<Object> get props => [product];
}

class RemoveProductFromCartEvent extends BillingEvent {
  final String productId;
  const RemoveProductFromCartEvent(this.productId);
  @override
  List<Object> get props => [productId];
}

class UpdateQuantityEvent extends BillingEvent {
  final String productId;
  final int quantity;
  const UpdateQuantityEvent(this.productId, this.quantity);
  @override
  List<Object> get props => [productId, quantity];
}

class ClearCartEvent extends BillingEvent {}

class PrintReceiptEvent extends BillingEvent {
  final String shopName;
  final String address1;
  final String address2;
  final String phone;
  final String footer;

  const PrintReceiptEvent({
    required this.shopName,
    required this.address1,
    required this.address2,
    required this.phone,
    required this.footer,
  });

  @override
  List<Object> get props => [shopName, address1, address2, phone, footer];
}

class SetPaymentMethodEvent extends BillingEvent {
  final PaymentMethod method;
  const SetPaymentMethodEvent(this.method);
  @override
  List<Object> get props => [method];
}

class ApplyDiscountEvent extends BillingEvent {
  final double amount;
  const ApplyDiscountEvent(this.amount);
  @override
  List<Object> get props => [amount];
}

class SetItemDiscountEvent extends BillingEvent {
  final String productId;
  final double discountAmount;
  const SetItemDiscountEvent(this.productId, this.discountAmount);
  @override
  List<Object> get props => [productId, discountAmount];
}

class SetAmountTenderedEvent extends BillingEvent {
  final double amount;
  const SetAmountTenderedEvent(this.amount);
  @override
  List<Object> get props => [amount];
}

class ProcessCashCheckoutEvent extends BillingEvent {}

class CreatePaymentIntentEvent extends BillingEvent {
  final String method;
  const CreatePaymentIntentEvent({this.method = 'card'});
  @override
  List<Object> get props => [method];
}

class CardScannedEvent extends BillingEvent {
  final String last4;
  final String? expiry;
  const CardScannedEvent(this.last4, this.expiry);
  @override
  List<Object> get props => <Object>[last4, expiry ?? ''];
}

class MoMoProviderSelectedEvent extends BillingEvent {
  final MoMoProvider provider;
  const MoMoProviderSelectedEvent(this.provider);
  @override
  List<Object> get props => [provider];
}

class MoMoPhoneEnteredEvent extends BillingEvent {
  final String phone;
  const MoMoPhoneEnteredEvent(this.phone);
  @override
  List<Object> get props => [phone];
}

class RequestMoMoCheckoutEvent extends BillingEvent {}

class MoMoChargePolledEvent extends BillingEvent {
  final String intentId;
  const MoMoChargePolledEvent(this.intentId);
  @override
  List<Object> get props => [intentId];
}

class CheckPaymentStatusEvent extends BillingEvent {
  final String intentId;
  const CheckPaymentStatusEvent(this.intentId);
  @override
  List<Object> get props => [intentId];
}

class CompleteCheckoutEvent extends BillingEvent {
  final String saleId;
  const CompleteCheckoutEvent(this.saleId);
  @override
  List<Object> get props => [saleId];
}

class ResetCheckoutEvent extends BillingEvent {}

// --- Split payments (POS-3) ---

/// Adds a new payment method allocation to a split payment. The first add
/// seeds the currently-selected single method as the initial entry so the
/// cashier can redistribute the total across methods.
class AddSplitPaymentEvent extends BillingEvent {
  final PaymentMethod method;
  const AddSplitPaymentEvent(this.method);
  @override
  List<Object> get props => [method];
}

/// Removes a split payment allocation by index.
class RemoveSplitPaymentEvent extends BillingEvent {
  final int index;
  const RemoveSplitPaymentEvent(this.index);
  @override
  List<Object> get props => [index];
}

/// Updates the amount allocated to a split payment entry.
class UpdateSplitPaymentAmountEvent extends BillingEvent {
  final int index;
  final double amount;
  const UpdateSplitPaymentAmountEvent(this.index, this.amount);
  @override
  List<Object> get props => [index, amount];
}

/// Changes the method of an existing split payment entry.
class UpdateSplitPaymentMethodEvent extends BillingEvent {
  final int index;
  final PaymentMethod method;
  const UpdateSplitPaymentMethodEvent(this.index, this.method);
  @override
  List<Object> get props => [index, method];
}

/// Exits split-payment mode and returns to single-payment selection.
class ClearSplitPaymentsEvent extends BillingEvent {}

/// Processes a checkout composed of multiple payment methods (POS-3).
class ProcessSplitCheckoutEvent extends BillingEvent {}

// --- Quick Sale (scanned barcode not in catalog) ---

/// Adds an ad-hoc quick-sale line item to the cart. The [name] and [price] are
/// entered by the cashier; a dummy [Product] is synthesised so the existing
/// checkout flow works unchanged.
class AddQuickSaleEvent extends BillingEvent {
  final String name;
  final double price;
  final int quantity;
  const AddQuickSaleEvent(this.name, this.price, this.quantity);
  @override
  List<Object> get props => [name, price, quantity];
}

/// Clears the `notFoundBarcode` prompt flag after the Quick Sale dialog has
/// been dismissed so the same barcode can re-trigger the dialog on a later scan.
class ClearQuickSalePromptEvent extends BillingEvent {}

// --- Smart Quick Sale Suggestions ---

/// Loads quick sale suggestions (items sold frequently as quick sales that
/// could be promoted to the catalog). Results populate `quickSaleSuggestions`.
class LoadQuickSaleSuggestionsEvent extends BillingEvent {}

/// Dismisses a quick sale suggestion. When [permanent] is true the suggestion
/// is denylisted forever ("Never"); when false it is hidden for today ("Later").
class DismissQuickSaleSuggestionEvent extends BillingEvent {
  final String name;
  final bool permanent;
  const DismissQuickSaleSuggestionEvent(this.name, this.permanent);
  @override
  List<Object> get props => [name, permanent];
}

/// Promotes a quick sale item into the catalog by inserting a product (and an
/// inventory row) into Supabase, then removes the suggestion from the list.
class AddQuickSaleToCatalogEvent extends BillingEvent {
  final String name;
  final double price;
  final String category;
  const AddQuickSaleToCatalogEvent(this.name, this.price, this.category);
  @override
  List<Object> get props => [name, price, category];
}
