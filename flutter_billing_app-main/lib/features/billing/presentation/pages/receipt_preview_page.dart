import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/printer_helper.dart';

/// A single line item on the receipt, snapped from [BillingState.cartItems]
/// before the bloc is reset. Kept decoupled from the domain [CartItem] so the
/// receipt preview can render even after the checkout state is cleared.
class ReceiptLineItem {
  final String name;
  final int quantity;
  final double unitPrice;

  const ReceiptLineItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => unitPrice * quantity;
}

/// One payment allocation shown on the receipt. For a single-payment sale this
/// list contains one entry; for a split payment (POS-3) it contains one entry
/// per method.
class ReceiptPayment {
  final String label;
  final double amount;

  const ReceiptPayment({required this.label, required this.amount});
}

/// Immutable snapshot of a finalized sale, passed to [ReceiptPreviewPage] via
/// the go_router `extra` payload.
class ReceiptData {
  final String? saleId;
  final List<ReceiptLineItem> items;
  final double subtotal;
  final double discount;
  final double total;
  final List<ReceiptPayment> payments;
  final double change;
  final bool wasQueued;

  const ReceiptData({
    required this.saleId,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.payments,
    this.change = 0,
    this.wasQueued = false,
  });
}

class ReceiptPreviewPage extends StatefulWidget {
  final ReceiptData data;

  const ReceiptPreviewPage({super.key, required this.data});

  @override
  State<ReceiptPreviewPage> createState() => _ReceiptPreviewPageState();
}

class _ReceiptPreviewPageState extends State<ReceiptPreviewPage> {
  bool _isPrinting = false;
  String? _shopName;
  String? _address1;
  String? _address2;
  String? _phone;

  @override
  void initState() {
    super.initState();
    _loadShopInfo();
  }

  Future<void> _loadShopInfo() async {
    String name = 'LedgerMind Store';
    String address1 = '';
    String address2 = '';
    String phone = '';

    try {
      final shopBox = HiveDatabase.shopBox;
      if (shopBox.isNotEmpty) {
        final shop = shopBox.values.first;
        name = shop.name.isNotEmpty ? shop.name : name;
        address1 = shop.addressLine1;
        address2 = shop.addressLine2;
        phone = shop.phoneNumber;
      }
    } catch (_) {
      // Fall back to settings box below.
    }

    final savedName = HiveDatabase.settingsBox.get('shop_name');
    if (savedName != null && savedName.toString().isNotEmpty) {
      name = savedName.toString();
    }

    if (mounted) {
      setState(() {
        _shopName = name;
        _address1 = address1;
        _address2 = address2;
        _phone = phone;
      });
    }
  }

  String get _formattedDateTime =>
      DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now());

  String get _invoiceNumber => widget.data.saleId ?? 'N/A';

  String get _qrPayload => widget.data.saleId ?? _invoiceNumber;

  Future<void> _printReceipt() async {
    setState(() => _isPrinting = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final printer = PrinterHelper();
      if (!printer.isConnected) {
        final savedMac = HiveDatabase.settingsBox.get('printer_mac');
        if (savedMac == null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('No printer paired. Pair one in Settings.'),
              backgroundColor: AppTheme.destructive,
            ),
          );
          setState(() => _isPrinting = false);
          return;
        }
        final connected = await printer.connect(savedMac);
        if (!connected) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to printer'),
              backgroundColor: AppTheme.destructive,
            ),
          );
          setState(() => _isPrinting = false);
          return;
        }
      }

      final items = widget.data.items
          .map((item) => {
                'name': item.name,
                'qty': item.quantity,
                'price': item.unitPrice.toStringAsFixed(2),
                'total': item.total.toStringAsFixed(2),
              })
          .toList();

      await printer.printReceipt(
        shopName: _shopName ?? 'LedgerMind Store',
        address1: _address1 ?? '',
        address2: _address2 ?? '',
        phone: _phone ?? '',
        items: items,
        total: widget.data.total,
        footer: widget.data.wasQueued
            ? 'OFFLINE PENDING - will sync when online'
            : 'Thank you!',
      );

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Receipt printed'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Print failed: $e'),
          backgroundColor: AppTheme.destructive,
        ),
      );
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  void _done() {
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _done();
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Receipt Preview',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.foreground)),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 16),
                child: Column(
                  children: [
                    _buildReceiptCard(),
                    const SizedBox(height: 16),
                    _buildQrCard(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            _buildBottomButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildShopHeader(),
          const _DashedDivider(),
          _buildMetaRow('Date', _formattedDateTime),
          _buildMetaRow('Invoice', _invoiceNumber),
          const _DashedDivider(),
          _buildItemsSection(),
          const _DashedDivider(),
          _buildTotalsSection(),
          const _DashedDivider(),
          _buildPaymentsSection(),
          if (widget.data.change > 0) ...[
            const SizedBox(height: 8),
            _buildChangeRow(),
          ],
          if (widget.data.wasQueued) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'OFFLINE SALE — pending sync',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.warning),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShopHeader() {
    return Column(
      children: [
        Text(
          _shopName ?? 'LedgerMind Store',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppTheme.foreground,
          ),
        ),
        if (_address1 != null && _address1!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(_address1!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.mutedForeground)),
        ],
        if (_address2 != null && _address2!.isNotEmpty)
          Text(_address2!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.mutedForeground)),
        if (_phone != null && _phone!.isNotEmpty)
          Text(_phone!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.mutedForeground)),
      ],
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.mutedForeground)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.foreground)),
        ],
      ),
    );
  }

  Widget _buildItemsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('ITEMS',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: AppTheme.mutedForeground)),
        ),
        ...widget.data.items.map((item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${item.quantity} x ${item.name}',
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.foreground),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'GHS ${item.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.foreground),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildTotalsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildAmountRow('Subtotal', widget.data.subtotal),
        if (widget.data.discount > 0)
          _buildAmountRow('Discount', -widget.data.discount,
              color: AppTheme.destructive),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('TOTAL',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.foreground)),
            Text(
              'GHS ${widget.data.total.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAmountRow(String label, double amount, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppTheme.mutedForeground)),
          Text(
            'GHS ${amount.toStringAsFixed(2)}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color ?? AppTheme.foreground),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('PAYMENT',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  color: AppTheme.mutedForeground)),
        ),
        ...widget.data.payments.map((p) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(p.label,
                      style: const TextStyle(
                          fontSize: 13, color: AppTheme.foreground)),
                  Text(
                    'GHS ${p.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.foreground),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildChangeRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Change Due',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.foreground)),
        Text(
          'GHS ${widget.data.change.toStringAsFixed(2)}',
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.success),
        ),
      ],
    );
  }

  Widget _buildQrCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const Text('Scan to verify sale',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.mutedForeground)),
          const SizedBox(height: 12),
          PrettyQrView.data(
            data: _qrPayload,
            decoration: const PrettyQrDecoration(
              shape: PrettyQrSmoothSymbol(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _invoiceNumber,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.mutedForeground),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons() {
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isPrinting ? null : _printReceipt,
                  icon: _isPrinting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_outlined),
                  label: const Text('Print Receipt',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _done,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.primaryForeground,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Done',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const dashWidth = 6.0;
          final dashCount = (constraints.maxWidth / (dashWidth * 2)).floor();
          return Row(
            children: List.generate(
              dashCount,
              (_) => Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  height: 1,
                  color: AppTheme.border,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
