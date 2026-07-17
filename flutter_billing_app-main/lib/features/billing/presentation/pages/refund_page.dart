import 'package:flutter/material.dart';
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
      appBar: AppBar(title: const Text('Refund / Return')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _saleIdController,
              decoration: const InputDecoration(
                labelText: 'Sale ID',
                hintText: 'Paste the sale UUID',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loading ? null : _lookup,
              child: const Text('Lookup Sale'),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('No sale items found'))
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          title: Text(item.productName),
                          subtitle: Text(
                            'Sold ${item.quantity}, already refunded ${item.refundedQuantity}, max ${item.maxRefundable}',
                          ),
                          trailing: SizedBox(
                            width: 80,
                            child: TextField(
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Qty'),
                              onChanged: (value) {
                                final qty = int.tryParse(value) ?? 0;
                                setState(() {
                                  _selected[item.id] = qty.clamp(0, item.maxRefundable);
                                });
                              },
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_items.isNotEmpty) ...[
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(labelText: 'Reason (optional)'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: const Text('Process Refund'),
              ),
            ],
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _message!,
                  style: TextStyle(color: _success ? Colors.green : Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
