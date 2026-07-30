import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/services/refund_service.dart';

class RefundPage extends StatefulWidget {
  const RefundPage({super.key});

  @override
  State<RefundPage> createState() => _RefundPageState();
}

class _RefundPageState extends State<RefundPage> {
  final _service = RefundService();
  final _saleIdController = TextEditingController();
  final _reasonController = TextEditingController();
  List<RefundableItem> _items = [];
  final Map<String, int> _selected = {};
  bool _loading = false;
  String? _message;
  bool _success = false;

  Future<void> _lookup() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      final items = await _service.getRefundableItems(_saleIdController.text.trim());
      setState(() {
        _items = items;
        _selected.clear();
      });
    } on Exception catch (e) {
      setState(() => _message = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    try {
      await _service.processRefund(
        saleId: _saleIdController.text.trim(),
        items: _selected,
        reason: _reasonController.text.isEmpty ? null : _reasonController.text,
      );
      setState(() {
        _message = 'Refund processed';
        _success = true;
        _items = [];
        _selected.clear();
      });
    } on Exception catch (e) {
      setState(() {
        _message = e.toString();
        _success = false;
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _saleIdController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const Divider(height: 1, thickness: 1, color: AppTheme.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSearchBar(),
                    const SizedBox(height: 20),
                    const Text(
                      'RECENT SALES',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.mutedForeground,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_loading && _items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppTheme.primary,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    else if (_items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            _message ?? 'No sale items found',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.mutedForeground,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _buildTransactionCard(item);
                        },
                      ),
                    if (_items.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildReasonField(),
                      const SizedBox(height: 12),
                      _buildProcessButton(),
                    ],
                    if (_message != null && _items.isEmpty)
                      const SizedBox.shrink()
                    else if (_message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _message!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _success ? AppTheme.success : AppTheme.destructive,
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    _buildRefundPolicyCard(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.chevron_left, size: 28, color: AppTheme.primary),
              onPressed: () => Navigator.of(context).maybePop(),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          const Text(
            'Process Refund',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.foreground,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return SizedBox(
      width: 342,
      height: 44,
      child: Material(
        color: AppTheme.muted,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _saleIdController,
                  onSubmitted: (_) => _lookup(),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.foreground,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Search by receipt no or product...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppTheme.mutedForeground,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 14),
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.search, size: 20, color: AppTheme.mutedForeground),
                onPressed: _loading ? null : _lookup,
                padding: const EdgeInsets.only(right: 10),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionCard(RefundableItem item) {
    final initial = item.productName.isNotEmpty
        ? item.productName[0].toUpperCase()
        : '?';
    final total = (item.unitPrice * item.quantity);
    final selectedQty = _selected[item.id] ?? 0;

    return Container(
      width: 342,
      height: 72,
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sold ${item.quantity} - Refunded ${item.refundedQuantity} - Max ${item.maxRefundable}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: AppTheme.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'GHS ${total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.foreground,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 34,
                    height: 24,
                    child: TextField(
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: AppTheme.foreground),
                      decoration: InputDecoration(
                        hintText: 'Qty',
                        hintStyle: const TextStyle(fontSize: 10, color: AppTheme.mutedForeground),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                        filled: true,
                        fillColor: AppTheme.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: const BorderSide(color: AppTheme.primary, width: 1),
                        ),
                      ),
                      onChanged: (value) {
                        final qty = int.tryParse(value) ?? 0;
                        setState(() {
                          _selected[item.id] = qty.clamp(0, item.maxRefundable);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 60,
                    height: 24,
                    child: Material(
                      color: AppTheme.destructive.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _loading
                            ? null
                            : () {
                                if (selectedQty <= 0) {
                                  setState(() {
                                    _selected[item.id] = 1.clamp(0, item.maxRefundable);
                                  });
                                }
                                _submit();
                              },
                        child: const Center(
                          child: Text(
                            'Refund',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.destructive,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReasonField() {
    return SizedBox(
      width: 342,
      child: TextField(
        controller: _reasonController,
        style: const TextStyle(fontSize: 13, color: AppTheme.foreground),
        decoration: InputDecoration(
          hintText: 'Reason (optional)',
          hintStyle: const TextStyle(fontSize: 13, color: AppTheme.mutedForeground),
          filled: true,
          fillColor: AppTheme.muted,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.primary, width: 1),
          ),
        ),
      ),
    );
  }

  Widget _buildProcessButton() {
    return SizedBox(
      width: 342,
      height: 44,
      child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primary,
          foregroundColor: AppTheme.primaryForeground,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.primaryForeground,
                ),
              )
            : const Text(
                'Process Refund',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
      ),
    );
  }

  Widget _buildRefundPolicyCard() {
    return Container(
      width: 342,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Refund Policy',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Refunds must be processed within 24 hours of the original sale. The amount will be reversed to the original payment method.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: AppTheme.foreground,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
