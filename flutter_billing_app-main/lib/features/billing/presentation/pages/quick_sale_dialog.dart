import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/supabase/session_manager.dart';

/// Result returned by [showQuickSaleDialog]. When the cashier confirms, this
/// carries the entered name, price, and quantity. `null` means the dialog was
/// cancelled.
class QuickSaleResult {
  final String name;
  final double price;
  final int quantity;

  const QuickSaleResult({
    required this.name,
    required this.price,
    required this.quantity,
  });
}

/// Result returned when the manager chooses "Add to Catalog Instead". Carries
/// the details needed to create a catalog product (name, price, barcode).
class QuickSaleAddToCatalogResult {
  final String name;
  final double price;
  final String barcode;

  const QuickSaleAddToCatalogResult({
    required this.name,
    required this.price,
    required this.barcode,
  });
}

/// Shows a bottom sheet that lets the cashier sell a scanned-but-unrecognised
/// barcode as a Quick Sale (name + price + quantity), or — if the user has
/// manager privileges — add it to the catalog instead.
///
/// Returns a [QuickSaleResult] when the cashier confirms the quick sale, a
/// [QuickSaleAddToCatalogResult] when the manager chooses to add to catalog,
/// or `null` when cancelled.
Future<dynamic> showQuickSaleDialog(
  BuildContext context, {
  required String barcode,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _QuickSaleSheet(barcode: barcode),
  );
}

class _QuickSaleSheet extends StatefulWidget {
  final String barcode;

  const _QuickSaleSheet({required this.barcode});

  @override
  State<_QuickSaleSheet> createState() => _QuickSaleSheetState();
}

class _QuickSaleSheetState extends State<_QuickSaleSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _qtyController = TextEditingController(text: '1');

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  bool _validate() {
    if (!_formKey.currentState!.validate()) return false;
    final qty = int.tryParse(_qtyController.text);
    return qty != null && qty > 0;
  }

  void _submitQuickSale() {
    if (!_validate()) return;
    Navigator.of(context).pop(QuickSaleResult(
      name: _nameController.text.trim(),
      price: double.tryParse(_priceController.text) ?? 0,
      quantity: int.tryParse(_qtyController.text) ?? 1,
    ));
  }

  void _submitAddToCatalog() {
    if (!_validate()) return;
    Navigator.of(context).pop(QuickSaleAddToCatalogResult(
      name: _nameController.text.trim(),
      price: double.tryParse(_priceController.text) ?? 0,
      barcode: widget.barcode,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 48,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Title
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.qr_code_2,
                          color: AppTheme.warning, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Product Not Found',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.foreground)),
                          SizedBox(height: 2),
                          Text(
                              'Enter details to sell this item as a Quick Sale',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.mutedForeground)),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.muted,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Scanned: ${widget.barcode}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.mutedForeground,
                        fontFamily: 'monospace'),
                  ),
                ),

                const SizedBox(height: 20),

                // Item name
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Item Name',
                    hintText: 'e.g. Bottled Water',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an item name';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Price
                TextFormField(
                  controller: _priceController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    hintText: '0.00',
                    prefixText: 'GHS ',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  validator: (value) {
                    final parsed = double.tryParse(value ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a valid price';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // Quantity
                TextFormField(
                  controller: _qtyController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    hintText: '1',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (value) {
                    final parsed = int.tryParse(value ?? '');
                    if (parsed == null || parsed <= 0) {
                      return 'Enter a valid quantity';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 28),

                // Add to Cart
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _submitQuickSale,
                    icon: const Icon(Icons.add_shopping_cart, size: 20),
                    label: const Text('Add to Cart',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.primaryForeground,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Manager-only: Add to Catalog Instead
                if (SessionManager.canManageBusiness) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _submitAddToCatalog,
                      icon: const Icon(Icons.library_add_outlined, size: 20),
                      label: const Text('Add to Catalog Instead'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.border),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Cancel
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel',
                        style: TextStyle(color: AppTheme.mutedForeground)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
