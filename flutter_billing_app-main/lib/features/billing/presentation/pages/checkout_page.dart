import 'package:billing_app/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/billing_bloc.dart';
import 'receipt_preview_page.dart';

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _discountController = TextEditingController();
  final _tenderedController = TextEditingController();
  final _momoPhoneController = TextEditingController();
  final List<TextEditingController> _splitAmountControllers = [];
  bool _didNavigate = false;

  @override
  void dispose() {
    _discountController.dispose();
    _tenderedController.dispose();
    _momoPhoneController.dispose();
    for (final c in _splitAmountControllers) {
      c.dispose();
    }
    super.dispose();
  }

  String _last4(String? cardNumber) {
    if (cardNumber == null || cardNumber.length < 4) return cardNumber ?? '';
    return cardNumber.substring(cardNumber.length - 4);
  }

  String _methodLabel(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'Cash';
      case PaymentMethod.momo:
        return 'MoMo';
      case PaymentMethod.card:
        return 'Card';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        context.read<BillingBloc>().add(ResetCheckoutEvent());
        context.go('/');
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Checkout',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.foreground)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left,
                size: 28, color: AppTheme.primary),
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
            if (state.checkoutSuccess && !_didNavigate) {
              _didNavigate = true;
              _momoPhoneController.clear();
              final data = _buildReceiptData(state);
              context.read<BillingBloc>().add(ResetCheckoutEvent());
              context.go('/receipt', extra: data);
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
                        _buildCartTable(billingState),
                        const SizedBox(height: 16),
                        _buildDiscountInput(billingState),
                        const SizedBox(height: 16),
                        if (billingState.splitPayments.isNotEmpty)
                          _buildSplitPaymentSection(billingState)
                        else ...[
                          _buildPaymentMethodSelector(billingState),
                          const SizedBox(height: 16),
                          if (billingState.paymentMethod == PaymentMethod.card)
                            _buildCardScannerPanel(billingState),
                          const SizedBox(height: 16),
                          if (billingState.paymentMethod == PaymentMethod.momo)
                            _buildMoMoPanel(billingState),
                          const SizedBox(height: 16),
                          if (billingState.paymentMethod == PaymentMethod.cash)
                            _buildCashInputs(billingState),
                          const SizedBox(height: 16),
                          _buildAddPaymentMethodButton(billingState),
                        ],
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

  Widget _buildCartTable(BillingState state) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          border: const TableBorder(
            horizontalInside: BorderSide(color: AppTheme.border),
            bottom: BorderSide(color: AppTheme.border),
          ),
          children: [
            TableRow(
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: AppTheme.border)),
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
                    '${item.quantity} x ${item.displayName}',
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
        const Text('Payment Method',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.foreground)),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildMethodButton(PaymentMethod.cash, 'Cash', Icons.payments_outlined, state),
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
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: () async {
              final result = await context.push('/card-scanner');
              if (result is Map<String, dynamic> && mounted) {
                final last4 = _last4(result['cardNumber'] as String?);
                final expiry = result['expiryDate'] as String?;
                context.read<BillingBloc>().add(CardScannedEvent(last4, expiry));
              }
            },
            icon: const Icon(Icons.camera_alt, color: AppTheme.primary),
            label: const Text('Scan Card', style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.w600)),
          ),
          if (state.cardLast4 != null) ...[
            const SizedBox(height: 12),
            Text(
              'Card: \u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022 ${state.cardLast4!}',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.foreground),
            ),
            Text('Expiry: ${state.cardExpiry ?? '-'}',
                style: const TextStyle(color: AppTheme.mutedForeground)),
            const SizedBox(height: 8),
            const Text(
              'Card data is sent directly to Paystack over TLS. '
              'Only last-4 and reference are stored.',
              style: TextStyle(fontSize: 11, color: AppTheme.mutedForeground),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMoMoPanel(BillingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('MoMo Provider',
              style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.foreground)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildMoMoProviderButton(MoMoProvider.mtn, 'MTN', state),
              const SizedBox(width: 8),
              _buildMoMoProviderButton(MoMoProvider.vodafone, 'Vodafone', state),
              const SizedBox(width: 8),
              _buildMoMoProviderButton(MoMoProvider.airteltigo, 'AT', state),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _momoPhoneController,
            decoration: const InputDecoration(
              labelText: 'Customer Phone Number',
              prefixText: '+233 ',
              hintText: 'e.g. 24XXXXXXX',
            ),
            keyboardType: TextInputType.phone,
            onChanged: (value) {
              context.read<BillingBloc>().add(MoMoPhoneEnteredEvent(value));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMoMoProviderButton(
      MoMoProvider provider, String label, BillingState state) {
    final selected = state.momoProvider == provider;
    return Expanded(
      child: OutlinedButton(
        onPressed: () => context.read<BillingBloc>().add(
              MoMoProviderSelectedEvent(provider),
            ),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? AppTheme.primary : AppTheme.card,
          side: BorderSide(
            color: selected ? AppTheme.primary : AppTheme.border,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: selected ? AppTheme.primaryForeground : AppTheme.foreground,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildMethodButton(PaymentMethod method, String label, IconData icon, BillingState state) {
    final selected = state.paymentMethod == method;
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => context.read<BillingBloc>().add(SetPaymentMethodEvent(method)),
        icon: Icon(icon, color: selected ? AppTheme.primaryForeground : AppTheme.foreground, size: 20),
        label: Text(label,
            style: TextStyle(
                color: selected ? AppTheme.primaryForeground : AppTheme.foreground,
                fontWeight: FontWeight.w600,
                fontSize: 12)),
        style: OutlinedButton.styleFrom(
          backgroundColor: selected ? AppTheme.primary : AppTheme.card,
          side: BorderSide(color: selected ? AppTheme.primary : AppTheme.border),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildCashInputs(BillingState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Amount Tendered',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.foreground)),
          const SizedBox(height: 8),
          TextField(
            controller: _tenderedController,
            decoration: const InputDecoration(
              prefixText: 'GHS ',
              hintText: '0.00',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
            onChanged: (value) {
              final amount = double.tryParse(value) ?? 0;
              context.read<BillingBloc>().add(SetAmountTenderedEvent(amount));
            },
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Change',
                  style: TextStyle(fontSize: 13, color: AppTheme.mutedForeground)),
              Text(
                'GHS ${state.change.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.success),
              ),
            ],
          ),
        ],
      ),
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
            style: TextStyle(fontWeight: FontWeight.w500, color: AppTheme.foreground),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            onPressed: state.paymentIntentId == null
                ? null
                : () {
                    if (state.paymentMethod == PaymentMethod.momo) {
                      context.read<BillingBloc>().add(
                            MoMoChargePolledEvent(state.paymentIntentId!),
                          );
                    } else {
                      context.read<BillingBloc>().add(
                            CheckPaymentStatusEvent(state.paymentIntentId!),
                          );
                    }
                  },
            label: 'Check Payment Status',
            icon: Icons.refresh,
            isLoading: state.isProcessing,
          ),
          if (state.paymentStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Status: ${state.paymentStatus}',
                  style: const TextStyle(color: AppTheme.mutedForeground)),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, BillingState state) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(24), right: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                  Text(
                    'GHS ${state.totalAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.foreground,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _canConfirm(state)
                      ? () => _confirmPayment(context, state)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.primaryForeground,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: state.isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primaryForeground,
                          ),
                        )
                      : Text(
                          _confirmLabel(state),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _confirmLabel(BillingState state) {
    if (state.splitPayments.isNotEmpty) {
      return 'Complete Split Sale';
    }
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
    if (state.splitPayments.isNotEmpty) {
      context.read<BillingBloc>().add(ProcessSplitCheckoutEvent());
      return;
    }
    if (state.paymentMethod == PaymentMethod.cash) {
      context.read<BillingBloc>().add(ProcessCashCheckoutEvent());
    } else if (state.paymentMethod == PaymentMethod.momo) {
      context.read<BillingBloc>().add(RequestMoMoCheckoutEvent());
    } else {
      context.read<BillingBloc>().add(const CreatePaymentIntentEvent(method: 'card'));
    }
  }

  bool _canConfirm(BillingState state) {
    if (state.isProcessing || state.cartItems.isEmpty) return false;
    if (state.splitPayments.isNotEmpty) {
      return state.splitBalanced;
    }
    return true;
  }

  ReceiptData _buildReceiptData(BillingState state) {
    final items = state.cartItems
        .map((item) => ReceiptLineItem(
              name: item.displayName,
              quantity: item.quantity,
              unitPrice: item.product.price,
            ))
        .toList();

    final List<ReceiptPayment> payments;
    double change = 0;
    if (state.splitPayments.isNotEmpty) {
      payments = state.splitPayments
          .map((p) =>
              ReceiptPayment(label: _methodLabel(p.method), amount: p.amount))
          .toList();
    } else {
      payments = [
        ReceiptPayment(
            label: _methodLabel(state.paymentMethod),
            amount: state.totalAmount),
      ];
      if (state.paymentMethod == PaymentMethod.cash) {
        change = state.change;
      }
    }

    return ReceiptData(
      saleId: state.saleId,
      items: items,
      subtotal: state.subtotal,
      discount: state.discountAmount,
      total: state.totalAmount,
      payments: payments,
      change: change,
      wasQueued: state.wasQueued,
    );
  }

  Widget _buildAddPaymentMethodButton(BillingState state) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showAddSplitMethodDialog(state),
        icon: const Icon(Icons.add_circle_outline,
            color: AppTheme.primary, size: 20),
        label: const Text('Add Payment Method (Split)',
            style: TextStyle(
                color: AppTheme.primary, fontWeight: FontWeight.w600)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.primary),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Future<void> _showAddSplitMethodDialog(BillingState state) async {
    final available = PaymentMethod.values
        .where((m) {
          if (state.splitPayments.isEmpty) return m != state.paymentMethod;
          return !state.splitPayments.any((p) => p.method == m);
        })
        .toList();

    if (available.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All payment methods are already added'),
          backgroundColor: AppTheme.warning,
        ),
      );
      return;
    }

    final chosen = await showDialog<PaymentMethod>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add payment method'),
        children: available
            .map((m) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, m),
                  child: Row(
                    children: [
                      Icon(_methodIcon(m), color: AppTheme.primary),
                      const SizedBox(width: 12),
                      Text(_methodLabel(m)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );

    if (chosen != null && mounted) {
      context.read<BillingBloc>().add(AddSplitPaymentEvent(chosen));
    }
  }

  IconData _methodIcon(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return Icons.payments_outlined;
      case PaymentMethod.momo:
        return Icons.phone_android;
      case PaymentMethod.card:
        return Icons.credit_card;
    }
  }

  Widget _buildSplitPaymentSection(BillingState state) {
    // Keep controllers in sync with the bloc's split entries.
    while (_splitAmountControllers.length < state.splitPayments.length) {
      _splitAmountControllers.add(TextEditingController());
    }
    while (_splitAmountControllers.length > state.splitPayments.length) {
      _splitAmountControllers.removeLast().dispose();
    }
    for (var i = 0; i < state.splitPayments.length; i++) {
      final controller = _splitAmountControllers[i];
      final parsed = double.tryParse(controller.text) ?? 0;
      // Only resync from bloc when the numeric values diverge (e.g. on
      // add/remove/reset), so we don't clobber the field while typing.
      if ((parsed - state.splitPayments[i].amount).abs() >= 0.005) {
        controller.text = state.splitPayments[i].amount == 0
            ? ''
            : state.splitPayments[i].amount.toStringAsFixed(2);
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Split Payment',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppTheme.foreground)),
              TextButton.icon(
                onPressed: () => context
                    .read<BillingBloc>()
                    .add(ClearSplitPaymentsEvent()),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Cancel Split'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.destructive),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...List.generate(state.splitPayments.length, (i) {
            final entry = state.splitPayments[i];
            return _buildSplitRow(state, i, entry);
          }),
          if (state.splitPayments.length < PaymentMethod.values.length) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAddSplitMethodDialog(state),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Method'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _buildRemainingBalanceRow(state),
        ],
      ),
    );
  }

  Widget _buildSplitRow(
      BillingState state, int index, SplitPayment entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<PaymentMethod>(
              key: ValueKey('split-method-$index-${entry.method}'),
              initialValue: entry.method,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(),
              ),
              items: PaymentMethod.values
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(_methodLabel(m)),
                      ))
                  .toList(),
              onChanged: (m) {
                if (m != null) {
                  context
                      .read<BillingBloc>()
                      .add(UpdateSplitPaymentMethodEvent(index, m));
                }
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _splitAmountControllers[index],
              decoration: const InputDecoration(
                isDense: true,
                prefixText: 'GHS ',
                hintText: '0.00',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))
              ],
              onChanged: (value) {
                final amount = double.tryParse(value) ?? 0;
                context
                    .read<BillingBloc>()
                    .add(UpdateSplitPaymentAmountEvent(index, amount));
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.remove_circle_outline,
                color: AppTheme.destructive),
            onPressed: () => context
                .read<BillingBloc>()
                .add(RemoveSplitPaymentEvent(index)),
          ),
        ],
      ),
    );
  }

  Widget _buildRemainingBalanceRow(BillingState state) {
    final remaining = state.remainingBalance;
    final balanced = state.splitBalanced;
    final color = balanced
        ? AppTheme.success
        : (remaining > 0 ? AppTheme.warning : AppTheme.destructive);
    final label = balanced
        ? 'Fully allocated'
        : (remaining > 0
            ? 'Remaining: GHS ${remaining.toStringAsFixed(2)}'
            : 'Overpaid by GHS ${(-remaining).toStringAsFixed(2)}');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Allocated: GHS ${state.splitTotal.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.mutedForeground)),
          Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
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
          color: AppTheme.mutedForeground,
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
          color: isSubtitle ? AppTheme.mutedForeground : AppTheme.foreground,
        ),
      ),
    );
  }
}
