import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../billing/domain/entities/cart_item.dart';

enum PendingOperationType {
  sale,
  refund,
  paystackIntent,
  inventoryAdjustment,
}

class PendingOperation {
  final String id;
  final PendingOperationType type;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int attempts;
  String? lastError;
  DateTime? deadLetteredAt;
  String? deadLetterReason;

  PendingOperation({
    required this.id,
    required this.type,
    required this.idempotencyKey,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.deadLetteredAt,
    this.deadLetterReason,
  });

  bool get isDeadLettered => deadLetteredAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'idempotency_key': idempotencyKey,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
        if (deadLetteredAt != null)
          'dead_lettered_at': deadLetteredAt!.toIso8601String(),
        if (deadLetterReason != null) 'dead_letter_reason': deadLetterReason,
      };

  factory PendingOperation.fromJson(Map<String, dynamic> json) =>
      PendingOperation(
        id: json['id'] as String,
        type: PendingOperationType.values.byName(json['type'] as String),
        idempotencyKey: json['idempotency_key'] as String,
        payload: json['payload'] as Map<String, dynamic>,
        createdAt: DateTime.parse(json['created_at'] as String),
        attempts: json['attempts'] as int,
        lastError: json['last_error'] as String?,
        deadLetteredAt: json['dead_lettered_at'] != null
            ? DateTime.parse(json['dead_lettered_at'] as String)
            : null,
        deadLetterReason: json['dead_letter_reason'] as String?,
      );
}

class OfflineQueueService {
  static const String _boxName = 'offline_queue';
  static const String _deadLetterBoxName = 'offline_queue_dead_letter';
  static const int _defaultMaxAttempts = 5;

  /// Per-op-type attempt caps. Override here if a given op type should tolerate
  /// more (or fewer) retries before being dead-lettered.
  static const Map<PendingOperationType, int> _maxAttemptsByType = {
    PendingOperationType.sale: 5,
    PendingOperationType.refund: 5,
    PendingOperationType.paystackIntent: 5,
    PendingOperationType.inventoryAdjustment: 5,
  };

  final _uuid = const Uuid();
  Box<String>? _box;
  Box<String>? _deadLetterBox;
  bool _initialized = false;

  int maxAttemptsFor(PendingOperationType type) =>
      _maxAttemptsByType[type] ?? _defaultMaxAttempts;

  Future<void> init() async {
    if (_initialized) return;
    _box = await Hive.openBox<String>(_boxName);
    _deadLetterBox = await Hive.openBox<String>(_deadLetterBoxName);
    _initialized = true;
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    if (_box == null) return [];
    final ops = _box!.values
        .map((json) => PendingOperation.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();
    ops.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ops;
  }

  Future<List<PendingOperation>> getPendingByType(
      PendingOperationType type) async {
    final ops = await getPendingOperations();
    return ops.where((o) => o.type == type).toList();
  }

  Future<List<PendingOperation>> getPendingSales() =>
      getPendingByType(PendingOperationType.sale);

  Future<List<PendingOperation>> getPendingRefunds() =>
      getPendingByType(PendingOperationType.refund);

  Future<List<PendingOperation>> getPendingPaystackIntents() =>
      getPendingByType(PendingOperationType.paystackIntent);

  Future<PendingOperation> enqueueSale({
    required List<CartItem> items,
    required double discount,
    required double total,
  }) async {
    await init();
    final idempotencyKey = _uuid.v4();
    final id = _uuid.v4();

    final payload = {
      'items': items
          .map((item) => {
                'product_id': item.product.id,
                'quantity': item.quantity,
                'unit_price': item.product.price,
                'is_quick_sale': item.isQuickSale,
                if (item.isQuickSale) 'quick_sale_name': item.quickSaleName,
              })
          .toList(),
      'discount': discount,
      'total': total,
    };

    final operation = PendingOperation(
      id: id,
      type: PendingOperationType.sale,
      idempotencyKey: idempotencyKey,
      payload: payload,
      createdAt: DateTime.now(),
    );

    await _box?.put(id, jsonEncode(operation.toJson()));
    return operation;
  }

  /// Enqueues a refund for later sync. The idempotency key is generated once and
  /// reused on every retry so the server-side `process_refund` RPC can dedupe.
  Future<PendingOperation> enqueueRefund({
    required String saleId,
    required List<Map<String, dynamic>> items,
    String? reason,
    required String businessId,
    required String branchId,
    required String cashierId,
  }) async {
    await init();
    final idempotencyKey = _uuid.v4();
    final id = _uuid.v4();

    final payload = {
      'sale_id': saleId,
      'items': items,
      'reason': reason,
      'business_id': businessId,
      'branch_id': branchId,
      'cashier_id': cashierId,
    };

    final operation = PendingOperation(
      id: id,
      type: PendingOperationType.refund,
      idempotencyKey: idempotencyKey,
      payload: payload,
      createdAt: DateTime.now(),
    );

    await _box?.put(id, jsonEncode(operation.toJson()));
    return operation;
  }

  /// Enqueues a Paystack (card/MoMo) intent operation that failed mid-flight
  /// (e.g. `create_checkout_intent` succeeded but `paystack-initiate` failed).
  /// Retried on reconnect by re-initiating the charge against the same intent.
  Future<PendingOperation> enqueuePaystackIntent({
    required String intentId,
    required String reference,
    required String method,
  }) async {
    await init();
    final idempotencyKey = _uuid.v4();
    final id = _uuid.v4();

    final payload = {
      'intent_id': intentId,
      'reference': reference,
      'method': method,
    };

    final operation = PendingOperation(
      id: id,
      type: PendingOperationType.paystackIntent,
      idempotencyKey: idempotencyKey,
      payload: payload,
      createdAt: DateTime.now(),
    );

    await _box?.put(id, jsonEncode(operation.toJson()));
    return operation;
  }

  Future<void> removeOperation(String id) async {
    await _box?.delete(id);
  }

  Future<void> markAttempt(String id, String? error) async {
    final raw = _box?.get(id);
    if (raw == null) return;
    final op = PendingOperation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    op.attempts += 1;
    op.lastError = error;
    await _box?.put(id, jsonEncode(op.toJson()));
  }

  /// Replaces the old silent-deletion behaviour. Ops that have exhausted their
  /// per-type attempt cap are moved to the dead-letter box (preserved with the
  /// failure reason) instead of being deleted. The UI can later surface these
  /// via [getDeadLetteredOps] for manual reconciliation.
  Future<void> deadLetterExhausted() async {
    await init();
    final ops = await getPendingOperations();
    for (final op in ops) {
      if (op.attempts >= maxAttemptsFor(op.type)) {
        op.deadLetteredAt = DateTime.now();
        op.deadLetterReason = op.lastError ?? 'Max attempts exceeded';
        await _deadLetterBox?.put(op.id, jsonEncode(op.toJson()));
        await _box?.delete(op.id);
      }
    }
  }

  Future<List<PendingOperation>> getDeadLetteredOps() async {
    await init();
    if (_deadLetterBox == null) return [];
    final ops = _deadLetterBox!.values
        .map((json) => PendingOperation.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();
    ops.sort((a, b) =>
        (a.deadLetteredAt ?? a.createdAt).compareTo(b.deadLetteredAt ?? b.createdAt));
    return ops;
  }

  /// Manually re-queue a dead-lettered op for another sync attempt (e.g. after a
  /// manager reviews and fixes the underlying issue). Resets attempt count.
  Future<void> requeueFromDeadLetter(String id) async {
    await init();
    final raw = _deadLetterBox?.get(id);
    if (raw == null) return;
    final op = PendingOperation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    op.attempts = 0;
    op.lastError = null;
    op.deadLetteredAt = null;
    op.deadLetterReason = null;
    await _box?.put(op.id, jsonEncode(op.toJson()));
    await _deadLetterBox?.delete(id);
  }

  Future<int> pendingCount() async {
    if (_box == null) return 0;
    return _box!.length;
  }

  Future<int> deadLetterCount() async {
    await init();
    if (_deadLetterBox == null) return 0;
    return _deadLetterBox!.length;
  }

  Future<bool> isOnline() async {
    final results = await Connectivity().checkConnectivity();
    return results.isNotEmpty && results.any((r) => r != ConnectivityResult.none);
  }

  Stream<bool> get onConnectivityChanged {
    return Connectivity().onConnectivityChanged.map((results) =>
        results.isNotEmpty && results.any((r) => r != ConnectivityResult.none));
  }
}
