import '../../../billing/data/services/checkout_service.dart';
import 'offline_queue_service.dart';

class OfflineSyncService {
  final OfflineQueueService _queueService;
  final CheckoutService _checkoutService;
  bool _isProcessing = false;

  OfflineSyncService(this._queueService, this._checkoutService);

  Future<int> processPendingSales() async {
    if (_isProcessing) return 0;
    _isProcessing = true;

    int processed = 0;
    try {
      if (!await _queueService.isOnline()) {
        return 0;
      }

      final pending = await _queueService.getPendingSales();
      for (final op in pending) {
        try {
          final items = (op.payload['items'] as List<dynamic>)
              .cast<Map<String, dynamic>>();
          final discount = (op.payload['discount'] as num).toDouble();

          await _checkoutService.processCashCheckoutOffline(
            idempotencyKey: op.idempotencyKey,
            itemsJson: items,
            discount: discount,
          );

          await _queueService.removeOperation(op.id);
          processed++;
        } on Exception catch (e) {
          await _queueService.markAttempt(op.id, e.toString());
        }
      }
      await _queueService.clearCompleted();
    } finally {
      _isProcessing = false;
    }
    return processed;
  }

  void startListening() {
    _queueService.onConnectivityChanged.listen((isOnline) async {
      if (isOnline) {
        await processPendingSales();
      }
    });
  }
}
