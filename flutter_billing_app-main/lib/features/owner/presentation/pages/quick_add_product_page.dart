import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/services/barcode_lookup_service.dart';
import '../../../../core/services/barcode_lookup_result.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/owner_bloc.dart';

class QuickAddProductPage extends StatefulWidget {
  const QuickAddProductPage({super.key});

  @override
  State<QuickAddProductPage> createState() => _QuickAddProductPageState();
}

class _QuickAddProductPageState extends State<QuickAddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _barcodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  final _stockController = TextEditingController(text: '0');

  bool _isLookingUp = false;
  BarcodeLookupResult? _lookupResult;
  final List<String> _categorySuggestions = [
    'Beverages',
    'Snacks',
    'Groceries',
    'Household',
    'Personal Care',
    'Electronics',
    'Other',
  ];

  @override
  void dispose() {
    _barcodeController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _lookupBarcode() async {
    final barcode = _barcodeController.text.trim();
    if (barcode.isEmpty) return;

    setState(() => _isLookingUp = true);
    try {
      final result = await BarcodeLookupService().lookup(barcode);
      setState(() {
        _lookupResult = result;
        if (result != null) {
          _nameController.text = result.name;
          if (result.suggestedPrice != null) {
            _priceController.text = result.suggestedPrice!.toStringAsFixed(2);
          }
          if (result.category != null) {
            _categoryController.text = result.category!;
          }
        }
      });
    } catch (_) {
      // Swallow — user can fill manually.
    } finally {
      setState(() => _isLookingUp = false);
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;

    context.read<OwnerBloc>().add(QuickAddProduct(
          barcode: _barcodeController.text.trim(),
          name: _nameController.text.trim(),
          price: double.parse(_priceController.text.trim()),
          category: _categoryController.text.trim().isEmpty
              ? null
              : _categoryController.text.trim(),
          stockQty: int.tryParse(_stockController.text.trim()) ?? 0,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick Add Product')),
      body: BlocListener<OwnerBloc, OwnerState>(
        listenWhen: (prev, curr) =>
            prev.successMessage != curr.successMessage ||
            prev.error != curr.error,
        listener: (context, state) {
          if (state.successMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.successMessage!),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
            context.pop();
          }
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: AppTheme.destructive,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: BlocBuilder<OwnerBloc, OwnerState>(
          builder: (context, state) {
            if (state.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            return Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildBarcodeField(),
                  const SizedBox(height: 16),
                  _buildNameField(),
                  const SizedBox(height: 16),
                  _buildPriceField(),
                  const SizedBox(height: 16),
                  _buildCategoryField(),
                  const SizedBox(height: 16),
                  _buildStockField(),
                  const SizedBox(height: 24),
                  _buildSaveButton(),
                  if (_lookupResult != null) ...[
                    const SizedBox(height: 16),
                    _buildLookupInfo(),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBarcodeField() {
    return TextFormField(
      controller: _barcodeController,
      decoration: InputDecoration(
        labelText: 'Barcode',
        hintText: 'Scan or enter barcode',
        prefixIcon: const Icon(Icons.qr_code),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLookingUp)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: _lookupBarcode,
                tooltip: 'Lookup barcode',
              ),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                final barcode = await context.push<String>('/scanner');
                if (barcode != null && mounted) {
                  _barcodeController.text = barcode;
                  _lookupBarcode();
                }
              },
              tooltip: 'Scan barcode',
            ),
          ],
        ),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Barcode is required';
        }
        return null;
      },
      onChanged: (value) {
        // Clear lookup result when barcode changes.
        if (_lookupResult != null) {
          setState(() => _lookupResult = null);
        }
      },
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'Product Name',
        prefixIcon: Icon(Icons.label),
      ),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Name is required';
        }
        return null;
      },
    );
  }

  Widget _buildPriceField() {
    return TextFormField(
      controller: _priceController,
      decoration: const InputDecoration(
        labelText: 'Selling Price (GHS)',
        prefixIcon: Icon(Icons.payments),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Price is required';
        }
        final price = double.tryParse(value.trim());
        if (price == null || price < 0) {
          return 'Enter a valid price';
        }
        return null;
      },
    );
  }

  Widget _buildCategoryField() {
    return Autocomplete<String>(
      initialValue: TextEditingValue.empty,
      optionsBuilder: (textEditingValue) {
        final text = textEditingValue.text.toLowerCase();
        if (text.isEmpty) return _categorySuggestions;
        return _categorySuggestions
            .where((c) => c.toLowerCase().contains(text));
      },
      onSelected: (option) {
        _categoryController.text = option;
      },
      fieldViewBuilder:
          (context, controller, focusNode, onEditingComplete) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onEditingComplete: onEditingComplete,
          decoration: const InputDecoration(
            labelText: 'Category',
            prefixIcon: Icon(Icons.category),
          ),
        );
      },
    );
  }

  Widget _buildStockField() {
    return TextFormField(
      controller: _stockController,
      decoration: const InputDecoration(
        labelText: 'Initial Stock Quantity',
        prefixIcon: Icon(Icons.inventory),
      ),
      keyboardType: TextInputType.number,
      validator: (value) {
        final qty = int.tryParse(value?.trim() ?? '');
        if (qty == null || qty < 0) {
          return 'Enter a valid quantity';
        }
        return null;
      },
    );
  }

  Widget _buildSaveButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _save,
        icon: const Icon(Icons.save),
        label: const Text('Save Product',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildLookupInfo() {
    return Card(
      color: AppTheme.accent,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, color: AppTheme.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Auto-filled from barcode database${_lookupResult?.brand != null ? ' (${_lookupResult!.brand})' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
