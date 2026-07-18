import '../../../billing/data/services/checkout_service.dart';
import '../../../billing/data/services/refund_service.dart';
import '../../../../core/supabase/session_manager.dart';
import 'offline_queue_service.dart';

class OfflineSyncService {
  final OfflineQueueService _queueService;
  final CheckoutService _checkoutService;
  final RefundService _refundService;
  bool _isProcessing = false;
  bool _stopped = false;

  OfflineSyncService(
    this._queueService,
    this._checkoutService, {
    RefundService? refundService,
  }) : _refundService = refundService ?? RefundService();

  /// Stops the sync drain. Used by the token-refresh-failure handler
  /// (SYNC_PROTOCOL §3.2) so no further queue processing happens until the
  /// cashier re-authenticates. The queue itself is preserved.
  void stop() => _stopped = true;

  void start() => _stopped = false;

  Future<int> processPendingOperations() async {
    if (_isProcessing || _stopped) return 0;
    if (SessionManager.reLoginRequired) return 0;
    _isProcessing = true;

    int processed = 0;
    try {
      if (!await _queueService.isOnline()) {
        return 0;
      }

      final pending = await _queueService.getPendingOperations();
      for (final op in pending) {
        if (SessionManager.reLoginRequired) break;
        try {
          switch (op.type) {
            case PendingOperationType.sale:
              await _processSale(op);
              break;
            case PendingOperationType.refund:
              await _refundService.processQueuedRefund(op);
              break;
            case PendingOperationType.paystackIntent:
              await _processPaystackIntent(op);
              break;
            case PendingOperationType.inventoryAdjustment:
              // Not yet supported in the queue; skip without penalising.
              continue;
          }
          await _queueService.removeOperation(op.id);
          processed++;
        } on Exception catch (e) {
          await _queueService.markAttempt(op.id, e.toString());
        }
      }
      await _queueService.deadLetterExhausted();
    } finally {
      _isProcessing = false;
    }
    return processed;
  }

  Future<void> _processSale(PendingOperation op) async {
    final items = (op.payload['items'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final discount = (op.payload['discount'] as num).toDouble();

    await _checkoutService.processCashCheckoutOffline(
      idempotencyKey: op.idempotencyKey,
      itemsJson: items,
      discount: discount,
    );
  }

  /// Re-initiates a Paystack charge for an intent that failed mid-flight, then
  /// confirms via the intent status. The webhook remains the source of truth
  /// for finalization; we only remove the op once the intent is confirmed.
  Future<void> _processPaystackIntent(PendingOperation op) async {
    final intentId = op.payload['intent_id'] as String;
    await _checkoutService.initiatePaystackCharge(intentId);
    final status = await _checkoutService.checkPaymentStatus(intentId);
    if (status == null ||
        !(status == 'succeeded' ||
            status == 'confirmed' ||
            status == 'completed')) {
      // Still awaiting customer authorization / webhook; retry on next drain.
      throw Exception('Paystack intent $intentId not yet confirmed ($status)');
    }
  }

  void startListening() {
    _queueService.onConnectivityChanged.listen((isOnline) async {
      if (isOnline) {
        await processPendingOperations();
      }
    });
  }
}
