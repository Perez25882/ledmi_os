import 'package:billing_app/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../bloc/billing_bloc.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _discountController = TextEditingController();
  final _tenderedController = TextEditingController();
  String? _scannedCardLast4;
  String? _scannedExpiryDate;

  @override
  void dispose() {
    _discountController.dispose();
    _tenderedController.dispose();
    super.dispose();
  }

  String _last4(String? cardNumber) {
    if (cardNumber == null || cardNumber.length < 4) return cardNumber ?? '';
    return cardNumber.substring(cardNumber.length - 4);
  }

  @override
  Widget build(BuildContext context) {
    const borderColor = Color(0xFFE5E5EA);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        context.read<BillingBloc>().add(ResetCheckoutEvent());
        context.go('/');
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Checkout',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.chevron_left,
                size: 28, color: Theme.of(context).primaryColor),
            onPressed: () {
              context.read<BillingBloc>().add(ResetCheckoutEvent());
              context.go('/');
            },
          ),
        ),
        body: BlocConsumer<BillingBloc, BillingState>(
          listener: (context, state) {
            if (state.error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(state.error!),
                  backgroundColor: Colors.red,
                  behavior: SnackBarBehavior.floating,
                ),
              );
              context.read<BillingBloc>().add(ResetCheckoutEvent());
            }
            if (state.checkoutSuccess && state.cartItems.isEmpty) {
              setState(() {
                _scannedCardLast4 = null;
                _scannedExpiryDate = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Sale completed'),
                  backgroundColor: Colors.green,
                ),
              );
              context.read<BillingBloc>().add(ResetCheckoutEvent());
              context.go('/');
            }
          },
          builder: (context, billingState) {
            return Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    child: Column(
                      children: [
                        _buildCartTable(billingState, borderColor),
                        const SizedBox(height: 16),
                        _buildDiscountInput(billingState),
                        const SizedBox(height: 16),
                        _buildPaymentMethodSelector(billingState),
                        const SizedBox(height: 16),
                        if (billingState.paymentMethod == PaymentMethod.card)
                          _buildCardScannerPanel(billingState),
                        const SizedBox(height: 16),
                        if (billingState.paymentMethod == PaymentMethod.cash)
                          _buildCashInputs(billingState),
                        if (billingState.authorizationUrl != null)
                          _buildPaymentPendingPanel(billingState),
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
                _buildBottomBar(context, billingState),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCartTable(BillingState state, Color borderColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(color: borderColor),
            bottom: BorderSide(color: borderColor),
          ),
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: borderColor)),
              ),
              children: [
                _buildHeaderCell('Product', TextAlign.left),
                _buildHeaderCell('Price', TextAlign.right),
                _buildHeaderCell('Total', TextAlign.right),
              ],
            ),
            ...state.cartItems.map((item) {
              return TableRow(
                children: [
                  _buildDataCell(
                    '${item.quantity} x ${item.product.name}',
                    TextAlign.left,
                  ),
                  _buildDataCell(
                    'GHS ${item.product.price.toStringAsFixed(2)}',
                    TextAlign.right,
                    isSubtitle: true,
                  ),
                  _buildDataCell(
                    'GHS ${item.total.toStringAsFixed(2)}',
                    TextAlign.right,
                    isBold: true,
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscountInput(BillingState state) {
    return TextField(
      controller: _discountController,
      decoration: const InputDecoration(
        labelText: 'Discount (GHS)',
        border: OutlineInputBorder(),
        prefixText: 'GHS ',
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
      onChanged: (value) {
        final amount = double.tryParse(value) ?? 0;
        context.read<BillingBloc>().add(ApplyDiscountEvent(amount));
      },
    );
  }

  Widget _buildPaymentMethodSelector(BillingState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildMethodButton(PaymentMethod.cash, 'Cash', Icons.money, state),
            const SizedBox(width: 8),
            _buildMethodButton(PaymentMethod.momo, 'MoMo', Icons.phone_android, state),
            const SizedBox(width: 8),
            _buildMethodButton(PaymentMethod.card, 'Card', Icons.credit_card, state),
          ],
        ),
      ],
    );
  }

  Widget _buildCardScannerPanel(BillingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final result = await context.push('/card-scanner');
              if (result is Map<String, dynamic>) {
                setState(() {
                  _scannedCardLast4 = _last4(result['cardNumber'] as String?);
                  _scannedExpiryDate = result['expiryDate'] as String?;
                });
              }
            },
            icon: const Icon(Icons.camera_alt),
            label: const Text('Scan Card'),
          ),
          if (_scannedCardLast4 != null) ...[
            const SizedBox(height: 12),
            Text(
              'Card: •••• •••• •••• ${_scannedCardLast4!}',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            Text('Expiry: ${_scannedExpiryDate ?? '-'}'),
          ],
        ],
      ),
    );
  }

  Widget _buildMethodButton(PaymentMethod method, String label, IconData icon, BillingState state) {
    final selected = state.paymentMethod == method;
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => context.read<BillingBloc>().add(SetPaymentMethodEvent(method)),
        icon: Icon(icon, color: selected ? Colors.white : Colors.black87),
        label: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.black87)),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? Theme.of(context).primaryColor : Colors.white,
          side: BorderSide(color: selected ? Theme.of(context).primaryColor : const Color(0xFFE5E5EA)),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCashInputs(BillingState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _tenderedController,
          decoration: const InputDecoration(
            labelText: 'Amount Tendered (GHS)',
            border: OutlineInputBorder(),
            prefixText: 'GHS ',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
          onChanged: (value) {
            final amount = double.tryParse(value) ?? 0;
            context.read<BillingBloc>().add(SetAmountTenderedEvent(amount));
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Change: GHS ${state.change.toStringAsFixed(2)}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildPaymentPendingPanel(BillingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Payment window opened. Ask the customer to complete payment.',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            onPressed: state.paymentIntentId == null
                ? null
                : () => context.read<BillingBloc>().add(
                      CheckPaymentStatusEvent(state.paymentIntentId!),
                    ),
            label: 'Check Payment Status',
            icon: Icons.refresh,
            isLoading: state.isProcessing,
          ),
          if (state.paymentStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Status: ${state.paymentStatus}'),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, BillingState state) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(24), right: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'TOTAL',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    'GHS ${state.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                onPressed: state.isProcessing || state.cartItems.isEmpty
                    ? null
                    : () => _confirmPayment(context, state),
                label: _confirmLabel(state),
                icon: Icons.payment,
                isLoading: state.isProcessing,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _confirmLabel(BillingState state) {
    switch (state.paymentMethod) {
      case PaymentMethod.cash:
        return 'Complete Cash Sale';
      case PaymentMethod.momo:
        return 'Open MoMo Payment';
      case PaymentMethod.card:
        return 'Open Card Payment';
    }
  }

  void _confirmPayment(BuildContext context, BillingState state) {
    if (state.paymentMethod == PaymentMethod.cash) {
      context.read<BillingBloc>().add(ProcessCashCheckoutEvent());
    } else {
      context.read<BillingBloc>().add(CreatePaymentIntentEvent());
    }
  }

  Widget _buildHeaderCell(String text, TextAlign align) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Text(
        text.toUpperCase(),
        textAlign: align,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildDataCell(String text, TextAlign align,
      {bool isBold = false, bool isSubtitle = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: isSubtitle ? 12 : 14,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          color: isSubtitle ? Colors.grey[500] : Colors.black87,
        ),
      ),
    );
  }
}
