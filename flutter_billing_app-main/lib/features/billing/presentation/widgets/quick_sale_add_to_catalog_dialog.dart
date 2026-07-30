import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';

/// Result returned by [showQuickSaleAddToCatalogDialog]. Carries the details
/// entered by the cashier for promoting a quick sale item into the catalog.
/// `null` is returned when the dialog is cancelled.
class QuickSaleCatalogEntry {
  final String name;
  final double price;
  final String category;
  final String barcode;
  final int initialStock;

  const QuickSaleCatalogEntry({
    required this.name,
    required this.price,
    required this.category,
    required this.barcode,
    required this.initialStock,
  });
}

/// Shows a bottom sheet that lets the cashier promote a frequently-sold quick
/// sale item into the product catalog.
///
/// [name] and [avgPrice] are pre-filled from the suggestion but remain
/// editable. Returns a [QuickSaleCatalogEntry] when the cashier confirms, or
/// `null` when cancelled.
Future<QuickSaleCatalogEntry?> showQuickSaleAddToCatalogDialog(
  BuildContext context, {
  required String name,
  required double avgPrice,
}) {
  return showModalBottomSheet<QuickSaleCatalogEntry>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _AddToCatalogSheet(
      name: name,
      avgPrice: avgPrice,
    ),
  );
}

class _AddToCatalogSheet extends StatefulWidget {
  final String name;
  final double avgPrice;

  const _AddToCatalogSheet({
    required this.name,
    required this.avgPrice,
  });

  @override
  State<_AddToCatalogSheet> createState() => _AddToCatalogSheetState();
}

class _AddToCatalogSheetState extends State<_AddToCatalogSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  final _categoryController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _stockController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _priceController = TextEditingController(
      text: widget.avgPrice > 0
          ? widget.avgPrice.toStringAsFixed(2)
          : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    _barcodeController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(QuickSaleCatalogEntry(
      name: _nameController.text.trim(),
      price: double.tryParse(_priceController.text) ?? 0,
      category: _categoryController.text.trim(),
      barcode: _barcodeController.text.trim(),
      initialStock: int.tryParse(_stockController.text) ?? 0,
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
                        color: AppTheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_circle_outline,
                          color: AppTheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Add to Catalog',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.foreground)),
                          SizedBox(height: 2),
                          Text(
                              'Save this quick sale item as a catalog product',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.mutedForeground)),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // Product name
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Product Name',
                    hintText: 'e.g. Bottled Water',
                    prefixIcon: Icon(Icons.label_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a product name';
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

                // Category
                TextFormField(
                  controller: _categoryController,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    hintText: 'e.g. Drinks',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                ),

                const SizedBox(height: 16),

                // Barcode (optional)
                TextFormField(
                  controller: _barcodeController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Barcode (optional)',
                    hintText: 'Scan or enter a barcode',
                    prefixIcon: Icon(Icons.qr_code_2),
                  ),
                ),

                const SizedBox(height: 16),

                // Initial stock quantity (optional)
                TextFormField(
                  controller: _stockController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Initial Stock Quantity',
                    hintText: '0',
                    prefixIcon: Icon(Icons.inventory_2_outlined),
                  ),
                  validator: (value) {
                    final parsed = int.tryParse(value ?? '');
                    if (parsed == null || parsed < 0) {
                      return 'Enter a valid quantity';
                    }
                    return null;
                  },
                ),

                const SizedBox(height: 24),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.foreground,
                          side: const BorderSide(color: AppTheme.border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: AppTheme.primaryForeground,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Add to Catalog',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
