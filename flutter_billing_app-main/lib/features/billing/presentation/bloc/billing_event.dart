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
