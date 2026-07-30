import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_vibrate/flutter_vibrate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../../billing/presentation/bloc/billing_bloc.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../../../core/service_locator.dart' as di;
import '../../data/services/shift_service.dart';
import '../../domain/entities/cart_item.dart';
import '../widgets/quick_sale_suggestion_banner.dart';
import 'quick_sale_dialog.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    returnImage: false,
  );

  bool _isCameraOn = true;
  bool _isFlashOn = false;

  // Cooldown mapping to prevent rapid firing of the same barcode
  final Map<String, DateTime> _lastScanTimes = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Surface smart quick sale suggestions (items sold frequently as quick
    // sales that could be promoted to the catalog).
    context.read<BillingBloc>().add(LoadQuickSaleSuggestionsEvent());
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    final List<Barcode> barcodes = capture.barcodes;
    final now = DateTime.now();

    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        final rawValue = barcode.rawValue!;

        // Cooldown logic: 2 seconds per identical barcode
        if (_lastScanTimes.containsKey(rawValue)) {
          final lastScan = _lastScanTimes[rawValue]!;
          if (now.difference(lastScan).inSeconds < 2) {
            continue;
          }
        }

        _lastScanTimes[rawValue] = now;

        // Vibrate
        final canVibrate = await Vibrate.canVibrate;
        if (canVibrate) {
          Vibrate.feedback(FeedbackType.success);
        }

        if (mounted) {
          context.read<BillingBloc>().add(ScanBarcodeEvent(rawValue));
        }
        break; // Process one barcode at a time per frame
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MultiBlocListener(
        listeners: [
          BlocListener<BillingBloc, BillingState>(
            listenWhen: (previous, current) =>
                previous.error != current.error && current.error != null,
            listener: (context, state) {
              if (state.error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.error!),
                    backgroundColor: Colors.red,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          BlocListener<BillingBloc, BillingState>(
            listenWhen: (previous, current) =>
                previous.notFoundBarcode != current.notFoundBarcode &&
                current.notFoundBarcode != null,
            listener: (context, state) async {
              final barcode = state.notFoundBarcode!;
              // Clear the prompt flag so the same barcode can re-trigger later.
              context
                  .read<BillingBloc>()
                  .add(ClearQuickSalePromptEvent());

              _scannerController.stop();
              final result = await showQuickSaleDialog(context,
                  barcode: barcode);
              if (_isCameraOn && mounted) _scannerController.start();

              if (result == null || !context.mounted) return;
              if (result is QuickSaleResult) {
                context.read<BillingBloc>().add(AddQuickSaleEvent(
                      result.name,
                      result.price,
                      result.quantity,
                    ));
              } else if (result is QuickSaleAddToCatalogResult) {
                // Manager chose to add to catalog — navigate to product form.
                await context.push('/product-form', extra: {
                  'barcode': result.barcode,
                  'name': result.name,
                  'price': result.price,
                });
                if (_isCameraOn && mounted) _scannerController.start();
              }
            },
          ),
        ],
        child: Stack(
          children: [
            // Smart Quick Sale suggestion banner (above the scanner section).
            Positioned(
              top: MediaQuery.of(context).padding.top,
              left: 0,
              right: 0,
              child: const QuickSaleSuggestionBanner(),
            ),

            // SCANNER VIEW (TOP 50%)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: MediaQuery.of(context).size.height * 0.4,
              child: _buildScannerSection(),
            ),

            // BOTTOM PANEL (BOTTOM 50% + OVERLAP)
            Positioned(
              top: (MediaQuery.of(context).size.height * 0.4) - 24, // overlap
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomPanel(),
            ),
          ],
        ),
      ),
      bottomSheet:
          BlocBuilder<BillingBloc, BillingState>(builder: (context, state) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: state.cartItems.isEmpty
                  ? null
                  : () async {
                      _scannerController.stop();
                      await context.push('/checkout');
                      if (_isCameraOn && mounted) _scannerController.start();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: AppTheme.primaryForeground,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                shadowColor: AppTheme.primary.withValues(alpha: 0.3),
              ),
              child: Text(
                state.cartItems.isEmpty
                    ? 'Review Order'
                    : 'Review Order  -  GHS ${state.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildScannerSection() {
    return Container(
      color: const Color(0xFF1E293B),
      child: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          if (!_isCameraOn) _buildCameraOffState(),

          // Overlay Actions (Top Right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Column(
              children: [
                _buildOverlayButton(
                  icon: Icons.settings,
                  onPressed: () async {
                    _scannerController.stop();
                    await context.push('/settings');
                    if (_isCameraOn && mounted) _scannerController.start();
                  },
                ),
                const SizedBox(height: 16),
                _buildOverlayButton(
                  icon: SessionManager.isShiftOpen ? Icons.lock_clock : Icons.lock_open,
                  color: SessionManager.isShiftOpen ? AppTheme.success : AppTheme.warning,
                  onPressed: () => _showShiftDialog(),
                ),
                const SizedBox(height: 16),
                _buildOverlayButton(
                  icon: Icons.assignment_return,
                  onPressed: () {
                    _scannerController.stop();
                    context.push('/refund');
                  },
                ),
                const SizedBox(height: 16),
                if (_isCameraOn)
                  _buildOverlayButton(
                    icon:
                        _isFlashOn ? Icons.flashlight_off : Icons.flashlight_on,
                    onPressed: () {
                      setState(() => _isFlashOn = !_isFlashOn);
                      _scannerController.toggleTorch();
                    },
                  ),
                if (_isCameraOn) const SizedBox(height: 16),
                _buildOverlayButton(
                  icon: _isCameraOn ? Icons.videocam : Icons.videocam_off,
                  // color:  Colors.white24 ,
                  onPressed: () {
                    setState(() {
                      _isCameraOn = !_isCameraOn;
                    });
                    if (_isCameraOn) {
                      _scannerController.start();
                    } else {
                      _scannerController.stop();
                    }
                  },
                ),
              ],
            ),
          ),

          // Connectivity indicator (Top Left)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            child: _buildConnectivityIndicator(),
          ),

          // Central Overlay Bounding Box
          if (_isCameraOn)
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Stack(
                  children: [
                    // Corners
                    _buildCorner(Alignment.topLeft),
                    _buildCorner(Alignment.topRight),
                    _buildCorner(Alignment.bottomLeft),
                    _buildCorner(Alignment.bottomRight),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCameraOffState() {
    return Container(
      color: const Color(0xFF1E293B),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFF334155),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child:
                const Icon(Icons.videocam_off, color: Colors.white70, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Camera is turned off',
            style: TextStyle(
                color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Turn on your camera to start scanning barcodes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.primaryForeground,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            icon: const Icon(Icons.videocam),
            label: const Text('Turn on Camera',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              setState(() => _isCameraOn = true);
              _scannerController.start();
            },
          )
        ],
      ),
    );
  }

  Widget _buildOverlayButton(
      {required IconData icon, required VoidCallback onPressed, Color? color}) {
    return Container(
      width: 44,
      height: 44,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: color ?? Colors.black.withValues(alpha: 0.4),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24),
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white, size: 20),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildConnectivityIndicator() {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      initialData: const [ConnectivityResult.none],
      builder: (context, snapshot) {
        final results = snapshot.data ?? const [ConnectivityResult.none];
        final isOnline = results.any((r) =>
            r != ConnectivityResult.none && r != ConnectivityResult.bluetooth);
        final dotColor = isOnline ? AppTheme.success : AppTheme.warning;
        final label = isOnline ? 'Online' : 'Offline';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showShiftDialog() async {
    final shiftService = di.sl<ShiftService>();
    final isOpen = SessionManager.isShiftOpen;

    if (isOpen) {
      final summary = await shiftService.getShiftSummary();
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Close Shift'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Shift opened: ${SessionManager.shiftOpenedAt?.toLocal()}'),
              const SizedBox(height: 8),
              Text('Float: GHS ${SessionManager.shiftFloat?.toStringAsFixed(2) ?? "0.00"}'),
              const SizedBox(height: 8),
              Text('Sales: ${summary.saleCount}'),
              Text('Cash: GHS ${summary.cashTotal.toStringAsFixed(2)}'),
              Text('Other: GHS ${summary.otherTotal.toStringAsFixed(2)}'),
              Text('Total: GHS ${summary.total.toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final actualCash = await _showCloseShiftInput(context, summary.cashTotal);
                if (actualCash == null) return;
                try {
                  await shiftService.closeShift(
                    shiftId: SessionManager.shiftId!,
                    actualCash: actualCash,
                  );
                  await SessionManager.closeShift();
                  setState(() {});
                  if (context.mounted) Navigator.of(context).pop();
                } on Exception catch (e) {
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text('Close Shift'),
            ),
          ],
        ),
      );
    } else {
      final floatController = TextEditingController();
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Open Shift'),
          content: TextField(
            controller: floatController,
            decoration: const InputDecoration(
              labelText: 'Opening Float (GHS)',
              prefixText: 'GHS ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final float = double.tryParse(floatController.text) ?? 0;
                try {
                  final shiftId = await shiftService.openShift(float);
                  await SessionManager.openShift(shiftId: shiftId, float: float);
                  setState(() {});
                  if (context.mounted) Navigator.of(context).pop();
                } on Exception catch (e) {
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: const Text('Open Shift'),
            ),
          ],
        ),
      );
    }
  }

  Future<double?> _showCloseShiftInput(BuildContext context, double expectedCash) async {
    final controller = TextEditingController(text: expectedCash.toStringAsFixed(2));
    double? result;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Actual Cash in Drawer'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Actual Cash (GHS)',
            prefixText: 'GHS ',
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              result = double.tryParse(controller.text);
              Navigator.of(context).pop();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return result;
  }

  Widget _buildCorner(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          border: Border(
            top: (alignment == Alignment.topLeft ||
                    alignment == Alignment.topRight)
                ? const BorderSide(color: AppTheme.primary, width: 4)
                : BorderSide.none,
            bottom: (alignment == Alignment.bottomLeft ||
                    alignment == Alignment.bottomRight)
                ? const BorderSide(color: AppTheme.primary, width: 4)
                : BorderSide.none,
            left: (alignment == Alignment.topLeft ||
                    alignment == Alignment.bottomLeft)
                ? const BorderSide(color: AppTheme.primary, width: 4)
                : BorderSide.none,
            right: (alignment == Alignment.topRight ||
                    alignment == Alignment.bottomRight)
                ? const BorderSide(color: AppTheme.primary, width: 4)
                : BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, -4))
        ],
      ),
      child: Column(
        children: [
          // Drag handle indicator
          Container(
            width: 48,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          BlocBuilder<BillingBloc, BillingState>(
            builder: (context, state) {
              final totalItems =
                  state.cartItems.fold<int>(0, (sum, i) => sum + i.quantity);
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text('Current Order',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold,
                                color: AppTheme.foreground)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Text(
                            '$totalItems',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'GHS ${state.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.foreground),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(height: 1, color: AppTheme.border),

          // List View
          Expanded(
            child: Stack(children: [
              BlocBuilder<BillingBloc, BillingState>(
                builder: (context, state) {
                  if (state.cartItems.isEmpty) {
                    return _buildEmptyCart();
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.only(
                        left: 15, right: 15, top: 16, bottom: 100),
                    itemCount: state.cartItems.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final item = state.cartItems[index];
                      return _buildCartItemCard(context, item);
                    },
                  );
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppTheme.muted,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.shopping_basket_outlined, size: 40, color: AppTheme.mutedForeground),
          ),
          const SizedBox(height: 16),
          const Text('No items yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.foreground)),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Scan a barcode to add items to the order.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.mutedForeground, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(
    BuildContext context,
    CartItem item,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 2))
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Quantity badge
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${item.quantity}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Item info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        item.displayName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: AppTheme.foreground),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.isQuickSale) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppTheme.warning.withValues(alpha: 0.4)),
                        ),
                        child: const Text(
                          'Quick Sale',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.warning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'GHS ${item.product.price.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.mutedForeground),
                ),
                if (item.hasDiscount) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Discount: GHS ${item.discount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          // Total + quantity controls
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.hasDiscount)
                    Text(
                      'GHS ${(item.product.price * item.quantity).toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.mutedForeground,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  if (item.hasDiscount) const SizedBox(width: 6),
                  Text(
                    'GHS ${item.total.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.foreground),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _circularIconButton(
                      icon: Icons.local_offer_outlined,
                      color: item.hasDiscount ? AppTheme.warning : AppTheme.mutedForeground,
                      onPressed: () => _showItemDiscountDialog(context, item)),
                  const SizedBox(width: 4),
                  _circularIconButton(
                      icon: Icons.remove,
                      onPressed: () {
                        if (item.quantity > 1) {
                          context.read<BillingBloc>().add(UpdateQuantityEvent(
                              item.product.id, item.quantity - 1));
                        } else {
                          context
                              .read<BillingBloc>()
                              .add(RemoveProductFromCartEvent(item.product.id));
                        }
                      }),
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${item.quantity}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.foreground),
                    ),
                  ),
                  _circularIconButton(
                      icon: Icons.add,
                      onPressed: () {
                        context.read<BillingBloc>().add(UpdateQuantityEvent(
                            item.product.id, item.quantity + 1));
                      }),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circularIconButton(
      {required IconData icon,
      required VoidCallback onPressed,
      Color? color}) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Icon(icon, size: 20, color: color ?? AppTheme.mutedForeground),
      ),
    );
  }

  Future<void> _showItemDiscountDialog(
      BuildContext context, CartItem item) async {
    final amountController = TextEditingController(
        text: item.hasDiscount ? item.discount.toStringAsFixed(2) : '');
    final percentController = TextEditingController();
    bool isPercent = false;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Line Discount'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(
                    'Line total: GHS ${(item.product.price * item.quantity).toStringAsFixed(2)}',
                    style:
                        const TextStyle(color: AppTheme.mutedForeground, fontSize: 13)),
                const SizedBox(height: 16),
                ToggleButtons(
                  isSelected: [!isPercent, isPercent],
                  onPressed: (index) {
                    setDialogState(() => isPercent = index == 1);
                  },
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Amount'),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('Percent'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: isPercent ? percentController : amountController,
                  decoration: InputDecoration(
                    labelText: isPercent ? 'Discount (%)' : 'Discount (GHS)',
                    prefixText: isPercent ? '% ' : 'GHS ',
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  autofocus: true,
                ),
              ],
            ),
            actions: [
              if (item.hasDiscount)
                TextButton(
                  onPressed: () {
                    context
                        .read<BillingBloc>()
                        .add(SetItemDiscountEvent(item.product.id, 0));
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('Remove'),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final raw = isPercent
                      ? percentController.text
                      : amountController.text;
                  final value = double.tryParse(raw) ?? 0;
                  final lineTotal = item.product.price * item.quantity;
                  final discount =
                      isPercent ? (lineTotal * value / 100) : value;
                  context
                      .read<BillingBloc>()
                      .add(SetItemDiscountEvent(item.product.id, discount));
                  Navigator.of(dialogContext).pop();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );
  }

  // A floating Details/Checkout Button at the very bottom
  // Added a Stack wrapper below to overlay this button
}
