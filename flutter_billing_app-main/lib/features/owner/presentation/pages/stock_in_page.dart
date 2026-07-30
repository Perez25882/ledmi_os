import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/services/barcode_lookup_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/owner_bloc.dart';

class StockInPage extends StatefulWidget {
  /// Optional pre-selected product (id, name, barcode, selling_price,
  /// cost_price) passed from the low-stock predictions page so the owner can
  /// record a delivery without searching.
  final Map<String, dynamic>? preselectedProduct;

  const StockInPage({super.key, this.preselectedProduct});

  @override
  State<StockInPage> createState() => _StockInPageState();
}

class _StockInPageState extends State<StockInPage> {
  final _searchController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _costPriceController = TextEditingController();

  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedProduct;
  bool _isSearching = false;
  bool _isBarcodeLookup = false;

  // Fields for "add to catalog + stock" when barcode not found.
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _categoryController = TextEditingController();
  String? _scannedBarcode;
  bool _showAddToCatalog = false;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedProduct != null) {
      _selectedProduct = widget.preselectedProduct;
      _searchController.text =
          widget.preselectedProduct!['name'] as String? ?? '';
    }
    context.read<OwnerBloc>().add(LoadStockInLog());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    _costPriceController.dispose();
    _nameController.dispose();
    _priceController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _searchProducts(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final businessId = SessionManager.businessId;
      if (businessId == null) return;

      final rows = await SupabaseClientManager.client
          .from('products')
          .select('id, name, barcode, selling_price, cost_price')
          .eq('business_id', businessId)
          .filter('name', 'ilike', '%$query%')
          .limit(10);

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(rows);
        _isSearching = false;
      });
    } catch (_) {
      setState(() => _isSearching = false);
    }
  }

  Future<void> _lookupBarcode(String barcode) async {
    setState(() => _isBarcodeLookup = true);
    try {
      final businessId = SessionManager.businessId;
      if (businessId == null) return;

      // First check catalog.
      final rows = await SupabaseClientManager.client
          .from('products')
          .select('id, name, barcode, selling_price, cost_price')
          .eq('business_id', businessId)
          .eq('barcode', barcode)
          .limit(1);

      if (rows.isNotEmpty) {
        setState(() {
          _selectedProduct = rows.first;
          _searchController.text = rows.first['name'] as String? ?? '';
          _showAddToCatalog = false;
        });
        return;
      }

      // Not in catalog — use BarcodeLookupService.
      final result = await BarcodeLookupService().lookup(barcode);
      setState(() {
        _scannedBarcode = barcode;
        _showAddToCatalog = true;
        _nameController.text = result?.name ?? '';
        _priceController.text =
            result?.suggestedPrice?.toStringAsFixed(2) ?? '';
        _categoryController.text = result?.category ?? '';
      });
    } catch (_) {
      // Swallow — user can retry.
    } finally {
      setState(() => _isBarcodeLookup = false);
    }
  }

  void _selectProduct(Map<String, dynamic> product) {
    setState(() {
      _selectedProduct = product;
      _searchController.text = product['name'] as String? ?? '';
      _searchResults = [];
      _showAddToCatalog = false;
    });
  }

  void _recordDelivery() {
    final product = _selectedProduct;
    if (product == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Select a product first'),
            backgroundColor: AppTheme.destructive),
      );
      return;
    }

    final qty = int.tryParse(_quantityController.text);
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter a valid quantity'),
            backgroundColor: AppTheme.destructive),
      );
      return;
    }

    final costPrice = double.tryParse(_costPriceController.text);

    context.read<OwnerBloc>().add(RecordStockIn(
          productId: product['id'] as String,
          quantity: qty,
          costPrice: costPrice,
        ));
  }

  void _addToCatalogAndStock() {
    final barcode = _scannedBarcode;
    if (barcode == null || barcode.isEmpty) return;

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Enter a product name'),
            backgroundColor: AppTheme.destructive),
      );
      return;
    }

    final price = double.tryParse(_priceController.text) ?? 0;
    final qty = int.tryParse(_quantityController.text) ?? 0;
    final category = _categoryController.text.trim().isEmpty
        ? null
        : _categoryController.text.trim();

    context.read<OwnerBloc>().add(QuickAddProduct(
          barcode: barcode,
          name: name,
          price: price,
          category: category,
          stockQty: qty,
        ));
  }

  void _resetForm() {
    setState(() {
      _selectedProduct = null;
      _searchController.clear();
      _quantityController.text = '1';
      _costPriceController.clear();
      _showAddToCatalog = false;
      _scannedBarcode = null;
      _nameController.clear();
      _priceController.clear();
      _categoryController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receive Delivery')),
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
            _resetForm();
            context.read<OwnerBloc>().add(LoadStockInLog());
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
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSearchSection(),
                if (_showAddToCatalog) ...[
                  const SizedBox(height: 16),
                  _buildAddToCatalogSection(),
                ],
                if (_selectedProduct != null) ...[
                  const SizedBox(height: 16),
                  _buildSelectedProductCard(),
                ],
                const SizedBox(height: 16),
                _buildQuantityAndCost(),
                const SizedBox(height: 24),
                _buildRecordButton(state.isLoading),
                const SizedBox(height: 24),
                _buildStockInLog(state),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Find Product',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
        const SizedBox(height: 8),
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Search by name or scan barcode',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isBarcodeLookup
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final barcode = await context.push<String>('/scanner');
                      if (barcode != null && mounted) {
                        _lookupBarcode(barcode);
                      }
                    },
                  ),
          ),
          onChanged: _searchProducts,
        ),
        if (_isSearching)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        if (_searchResults.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._searchResults.map((row) => _buildSearchResultTile(row)),
        ],
      ],
    );
  }

  Widget _buildSearchResultTile(Map<String, dynamic> row) {
    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        title: Text(row['name'] as String? ?? 'Unknown'),
        subtitle: Text(row['barcode'] as String? ?? ''),
        trailing: Text(
          'GHS ${(row['selling_price'] as num?)?.toStringAsFixed(2) ?? '0.00'}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onTap: () => _selectProduct(row),
      ),
    );
  }

  Widget _buildSelectedProductCard() {
    final product = _selectedProduct!;
    return Card(
      color: AppTheme.accent,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: AppTheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product['name'] as String? ?? '',
                      style:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              )),
                  Text(product['barcode'] as String? ?? '',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _resetForm,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddToCatalogSection() {
    return Card(
      color: AppTheme.warning.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: AppTheme.warning, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Barcode $_scannedBarcode not in catalog. Add it below.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Product Name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _priceController,
              decoration: const InputDecoration(
                labelText: 'Selling Price (GHS)',
                isDense: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Text(
                'This will add the product to your catalog and record the delivery in one action.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                    )),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityAndCost() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _quantityController,
            decoration: const InputDecoration(
              labelText: 'Quantity Received',
              isDense: true,
            ),
            keyboardType: TextInputType.number,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _costPriceController,
            decoration: const InputDecoration(
              labelText: 'Cost Price (optional)',
              isDense: true,
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
      ],
    );
  }

  Widget _buildRecordButton(bool isLoading) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: isLoading
            ? null
            : _showAddToCatalog ? _addToCatalogAndStock : _recordDelivery,
        icon: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.inventory_2),
        label: Text(
          _showAddToCatalog ? 'Add to Catalog + Stock' : 'Record Delivery',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildStockInLog(OwnerState state) {
    if (state.stockInLog.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Icon(Icons.history, color: AppTheme.mutedForeground, size: 32),
              const SizedBox(height: 8),
              Text('No deliveries recorded today',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.mutedForeground,
                      )),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Today\'s Deliveries',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
        const SizedBox(height: 8),
        ...state.stockInLog.map((entry) => Card(
              margin: const EdgeInsets.only(bottom: 4),
              child: ListTile(
                leading: const Icon(Icons.arrow_downward, color: AppTheme.success),
                title: Text(entry.productName),
                subtitle: Text(
                    '${entry.quantity} units • ${_formatTime(entry.createdAt)}'),
                dense: true,
              ),
            )),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour > 12 ? dt.hour - 12 : dt.hour;
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute $amPm';
  }
}
