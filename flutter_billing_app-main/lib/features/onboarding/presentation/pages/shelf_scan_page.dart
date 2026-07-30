import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/services/barcode_lookup_result.dart';
import '../../../../core/services/barcode_lookup_service.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/onboarding_bloc.dart';

/// A single scanned item recorded during the shelf-scan step.
class ScannedItem {
  final String productId;
  final String name;
  final String barcode;
  final int quantity;
  final double price;

  const ScannedItem({
    required this.productId,
    required this.name,
    required this.barcode,
    required this.quantity,
    required this.price,
  });
}

class ShelfScanPage extends StatefulWidget {
  const ShelfScanPage({super.key});

  @override
  State<ShelfScanPage> createState() => _ShelfScanPageState();
}

class _ShelfScanPageState extends State<ShelfScanPage> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    returnImage: false,
  );

  bool _isCameraOn = true;
  bool _isFlashOn = false;
  bool _isProcessing = false;

  // Cooldown mapping to prevent rapid firing of the same barcode.
  final Map<String, DateTime> _lastScanTimes = {};

  final List<ScannedItem> _scannedItems = [];

  late final OnboardingBloc _bloc;
  late final BarcodeLookupService _lookupService;

  @override
  void initState() {
    super.initState();
    _bloc = context.read<OnboardingBloc>();
    _lookupService = BarcodeLookupService();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;
    final now = DateTime.now();

    for (final barcode in barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.isEmpty) continue;

      // Cooldown: 3 seconds per identical barcode.
      if (_lastScanTimes.containsKey(rawValue)) {
        final lastScan = _lastScanTimes[rawValue]!;
        if (now.difference(lastScan).inSeconds < 3) continue;
      }
      _lastScanTimes[rawValue] = now;

      await _handleScannedBarcode(rawValue);
      break; // Process one barcode at a time per frame.
    }
  }

  Future<void> _handleScannedBarcode(String barcode) async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    if (businessId == null || branchId == null) {
      _showError('No active business/branch session');
      return;
    }

    setState(() => _isProcessing = true);
    _scannerController.stop();

    try {
      // 1. Check if the product already exists in the catalog.
      final existing = await _bloc.service.findProductByBarcode(
        businessId: businessId,
        barcode: barcode,
      );

      if (existing != null) {
        if (!mounted) return;
        await _showSetQuantitySheet(
          productId: existing['id'] as String,
          name: existing['name'] as String,
          barcode: barcode,
          price: (existing['selling_price'] as num).toDouble(),
        );
        return;
      }

      // 2. Look up the barcode via the cache / Open Food Facts.
      final lookup = await _lookupService.lookup(barcode);

      if (lookup != null) {
        if (!mounted) return;
        await _showAddFromLookupSheet(barcode: barcode, lookup: lookup);
        return;
      }

      // 3. Not found anywhere — minimal manual entry form.
      if (!mounted) return;
      await _showManualEntrySheet(barcode: barcode);
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        if (_isCameraOn) _scannerController.start();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Bottom sheet: product found in catalog — set quantity only.
  // ---------------------------------------------------------------------------
  Future<void> _showSetQuantitySheet({
    required String productId,
    required String name,
    required String barcode,
    required double price,
  }) async {
    final qtyController = TextEditingController(text: '1');

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Product Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.foreground,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.foreground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'GHS ${price.toStringAsFixed(2)}  •  $barcode',
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.mutedForeground,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Set Quantity',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.foreground,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter stock quantity',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.primaryForeground,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Confirm',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    qtyController.dispose();

    if (result == true) {
      final qty = int.tryParse(qtyController.text) ?? 0;
      if (qty <= 0) {
        _showError('Quantity must be greater than 0');
        return;
      }
      await _confirmExistingProduct(
        productId: productId,
        name: name,
        barcode: barcode,
        price: price,
        quantity: qty,
      );
    }
  }

  Future<void> _confirmExistingProduct({
    required String productId,
    required String name,
    required String barcode,
    required double price,
    required int quantity,
  }) async {
    final businessId = SessionManager.businessId!;
    final branchId = SessionManager.branchId!;

    setState(() => _isProcessing = true);
    try {
      await _bloc.service.setInventoryQuantity(
        businessId: businessId,
        branchId: branchId,
        productId: productId,
        quantity: quantity,
      );
      _addScannedItem(ScannedItem(
        productId: productId,
        name: name,
        barcode: barcode,
        quantity: quantity,
        price: price,
      ));
      _showSuccess('Stock set: $name ($quantity)');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Bottom sheet: barcode lookup hit — pre-filled add-to-catalog form.
  // ---------------------------------------------------------------------------
  Future<void> _showAddFromLookupSheet({
    required String barcode,
    required BarcodeLookupResult lookup,
  }) async {
    final nameController = TextEditingController(text: lookup.name);
    final priceController = TextEditingController(
      text: lookup.suggestedPrice != null
          ? lookup.suggestedPrice!.toStringAsFixed(2)
          : '',
    );
    final qtyController = TextEditingController(text: '1');

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'Add to Catalog & Set Stock',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.foreground,
                ),
              ),
              const SizedBox(height: 12),
              if (lookup.category != null || lookup.brand != null)
                Text(
                  [
                    if (lookup.brand != null) lookup.brand!,
                    if (lookup.category != null) lookup.category!,
                  ].join('  •  '),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.mutedForeground,
                  ),
                ),
              if (lookup.category != null || lookup.brand != null)
                const SizedBox(height: 12),
              _buildLabel('Product Name'),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: 'Product name',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 16),
              _buildLabel('Selling Price (GHS)'),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 16),
              _buildLabel('Stock Quantity'),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter stock quantity',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.primaryForeground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Add to Catalog & Set Stock',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      final name = nameController.text.trim();
      final price = double.tryParse(priceController.text) ?? 0;
      final qty = int.tryParse(qtyController.text) ?? 0;
      nameController.dispose();
      priceController.dispose();
      qtyController.dispose();

      if (name.isEmpty || price <= 0 || qty <= 0) {
        _showError('Please fill all fields with valid values');
        return;
      }
      await _addProductFromBarcode(
        barcode: barcode,
        lookup: lookup,
        name: name,
        price: price,
        quantity: qty,
      );
    } else {
      nameController.dispose();
      priceController.dispose();
      qtyController.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Bottom sheet: barcode unknown — minimal manual entry form.
  // ---------------------------------------------------------------------------
  Future<void> _showManualEntrySheet({required String barcode}) async {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final qtyController = TextEditingController(text: '1');

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                'New Product',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.foreground,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Barcode: $barcode',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.mutedForeground,
                ),
              ),
              const SizedBox(height: 20),
              _buildLabel('Product Name'),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Enter product name',
                  prefixIcon: Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 16),
              _buildLabel('Selling Price (GHS)'),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  hintText: '0.00',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 16),
              _buildLabel('Stock quantity'),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  hintText: 'Enter stock quantity',
                  prefixIcon: Icon(Icons.inventory_2_outlined),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: AppTheme.primaryForeground,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Add Product & Set Stock',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true) {
      final name = nameController.text.trim();
      final price = double.tryParse(priceController.text) ?? 0;
      final qty = int.tryParse(qtyController.text) ?? 0;
      nameController.dispose();
      priceController.dispose();
      qtyController.dispose();

      if (name.isEmpty || price <= 0 || qty <= 0) {
        _showError('Please fill all fields with valid values');
        return;
      }
      await _addProductFromBarcode(
        barcode: barcode,
        lookup: null,
        name: name,
        price: price,
        quantity: qty,
      );
    } else {
      nameController.dispose();
      priceController.dispose();
      qtyController.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // Shared: insert a new product from a barcode (lookup or manual) + set stock.
  // ---------------------------------------------------------------------------
  Future<void> _addProductFromBarcode({
    required String barcode,
    required BarcodeLookupResult? lookup,
    required String name,
    required double price,
    required int quantity,
  }) async {
    final businessId = SessionManager.businessId!;
    final branchId = SessionManager.branchId!;

    setState(() => _isProcessing = true);
    try {
      final productId = await _bloc.service.addProductFromBarcode(
        businessId: businessId,
        branchId: branchId,
        barcode: barcode,
        lookupResult: lookup,
        price: price,
        stockQty: quantity,
        nameOverride: name,
      );
      _addScannedItem(ScannedItem(
        productId: productId,
        name: name,
        barcode: barcode,
        quantity: quantity,
        price: price,
      ));
      _showSuccess('Added: $name ($quantity)');
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  void _addScannedItem(ScannedItem item) {
    setState(() {
      // If the same product was scanned before, update the quantity.
      final idx = _scannedItems.indexWhere((e) => e.productId == item.productId);
      if (idx >= 0) {
        _scannedItems[idx] = ScannedItem(
          productId: item.productId,
          name: item.name,
          barcode: item.barcode,
          quantity: _scannedItems[idx].quantity + item.quantity,
          price: item.price,
        );
      } else {
        _scannedItems.insert(0, item);
      }
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.destructive,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _completeOnboarding() async {
    final businessId = SessionManager.businessId;
    if (businessId == null) {
      context.go('/');
      return;
    }
    setState(() => _isProcessing = true);
    _scannerController.stop();
    try {
      await _bloc.service.completeOnboarding(businessId);
      await SessionManager.setOnboardingCompleted(true);
    } catch (_) {
      // Best-effort — still navigate home so the user is not stuck.
    }
    if (mounted) {
      context.go('/');
    }
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppTheme.foreground,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 40,
                left: 24,
                right: 24,
                bottom: 24,
              ),
              decoration: const BoxDecoration(color: AppTheme.primary),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scan Your Shelves',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryForeground,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Scan product barcodes to set starting stock levels',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.primaryForeground,
                    ),
                  ),
                ],
              ),
            ),
            // Step indicator
            Padding(
              padding: const EdgeInsets.only(top: 16, left: 24, right: 24),
              child: Row(
                children: [
                  _stepDot(true),
                  _stepLine(true),
                  _stepDot(true),
                  _stepLine(true),
                  _stepDot(true),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Counter
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code_scanner,
                            size: 16, color: AppTheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          '${_scannedItems.length} products scanned',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Scanner view
            SizedBox(
              height: 220,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: _isCameraOn
                        ? MobileScanner(
                            controller: _scannerController,
                            onDetect: _onDetect,
                          )
                        : Container(
                            color: const Color(0xFF1E293B),
                            child: const Center(
                              child: Icon(Icons.videocam_off,
                                  color: Colors.white54, size: 40),
                            ),
                          ),
                  ),
                  // Scan frame overlay
                  if (_isCameraOn)
                    Center(
                      child: Container(
                        width: 200,
                        height: 120,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white54, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  // Flash toggle
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _buildOverlayButton(
                      icon: _isFlashOn
                          ? Icons.flashlight_on
                          : Icons.flashlight_off,
                      onPressed: () {
                        setState(() => _isFlashOn = !_isFlashOn);
                        _scannerController.toggleTorch();
                      },
                    ),
                  ),
                  // Camera toggle
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildOverlayButton(
                      icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                      onPressed: () {
                        setState(() => _isCameraOn = !_isCameraOn);
                        if (_isCameraOn) {
                          _scannerController.start();
                        } else {
                          _scannerController.stop();
                        }
                      },
                    ),
                  ),
                  if (_isProcessing)
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primaryForeground,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Recently scanned list
            Expanded(
              child: _scannedItems.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 40, color: AppTheme.mutedForeground),
                          SizedBox(height: 8),
                          Text(
                            'Scanned items will appear here',
                            style: TextStyle(
                              color: AppTheme.mutedForeground,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      itemCount: _scannedItems.length,
                      itemBuilder: (context, index) {
                        final item = _scannedItems[index];
                        return _ScannedTile(item: item);
                      },
                    ),
            ),
            // Footer buttons
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppTheme.card,
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : _completeOnboarding,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.foreground,
                        side: const BorderSide(color: AppTheme.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _completeOnboarding,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: AppTheme.primaryForeground,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Finish',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlayButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _stepDot(bool active) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: active ? AppTheme.primary : AppTheme.muted,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          active ? '3' : '•',
          style: TextStyle(
            color: active
                ? AppTheme.primaryForeground
                : AppTheme.mutedForeground,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _stepLine(bool active) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: active ? AppTheme.primary : AppTheme.border,
      ),
    );
  }
}

class _ScannedTile extends StatelessWidget {
  final ScannedItem item;

  const _ScannedTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: AppTheme.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border, width: 1),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.check,
                  size: 20, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.foreground,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'GHS ${item.price.toStringAsFixed(2)}  •  ${item.barcode}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'x${item.quantity}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
