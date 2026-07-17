import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../../../billing/domain/entities/cart_item.dart';

enum PendingOperationType { sale, refund, inventoryAdjustment }

class PendingOperation {
  final String id;
  final PendingOperationType type;
  final String idempotencyKey;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  int attempts;
  String? lastError;

  PendingOperation({
    required this.id,
    required this.type,
    required this.idempotencyKey,
    required this.payload,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'idempotency_key': idempotencyKey,
        'payload': payload,
        'created_at': createdAt.toIso8601String(),
        'attempts': attempts,
        'last_error': lastError,
      };

  factory PendingOperation.fromJson(Map<String, dynamic> json) => PendingOperation(
        id: json['id'] as String,
        type: PendingOperationType.values.byName(json['type'] as String),
        idempotencyKey: json['idempotency_key'] as String,
        payload: json['payload'] as Map<String, dynamic>,
        createdAt: DateTime.parse(json['created_at'] as String),
        attempts: json['attempts'] as int,
        lastError: json['last_error'] as String?,
      );
}

class OfflineQueueService {
  static const String _boxName = 'offline_queue';
  static const int _maxAttempts = 5;

  final _uuid = const Uuid();
  Box<String>? _box;

  Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  Future<List<PendingOperation>> getPendingOperations() async {
    if (_box == null) return [];
    final ops = _box!.values
        .map((json) => PendingOperation.fromJson(jsonDecode(json) as Map<String, dynamic>))
        .toList();
    ops.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return ops;
  }

  Future<List<PendingOperation>> getPendingSales() async {
    final ops = await getPendingOperations();
    return ops.where((o) => o.type == PendingOperationType.sale).toList();
  }

  Future<PendingOperation> enqueueSale({
    required List<CartItem> items,
    required double discount,
    required double total,
  }) async {
    final idempotencyKey = _uuid.v4();
    final id = _uuid.v4();

    final payload = {
      'items': items
          .map((item) => {
                'product_id': item.product.id,
                'quantity': item.quantity,
                'unit_price': item.product.price,
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

  Future<void> clearCompleted() async {
    final ops = await getPendingOperations();
    for (final op in ops) {
      if (op.attempts >= _maxAttempts) {
        await _box?.delete(op.id);
      }
    }
  }

  Future<int> pendingCount() async {
    if (_box == null) return 0;
    return _box!.length;
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
