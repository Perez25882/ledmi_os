import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../product/data/models/product_model.dart';

/// Reason a cached catalog row changed during a sync, per SYNC_PROTOCOL §4.4.
enum CatalogConflictReason { updated, deleted, outOfStock }

/// Signal emitted when a product in the active cart may need cashier action.
/// The UI/billing layer (owner B1) is expected to cross-reference these
/// product ids against the live cart — this client only emits the signal.
class CatalogConflictEvent {
  final String productId;
  final CatalogConflictReason reason;
  const CatalogConflictEvent(this.productId, this.reason);

  @override
  String toString() => 'CatalogConflictEvent($productId, $reason)';
}

/// Delta sync engine for the product catalog.
///
/// Implements SYNC_PROTOCOL §4.3: `get_catalog_delta(p_since)` polling with a
/// persisted `sync_meta.last_product_sync_at` cursor, plus an optional Realtime
/// subscription on `business:{id}:branch:{id}:catalog`. Falls back to 60s
/// polling when Realtime is unavailable or the device is offline.
class DeltaSyncClient {
  static const String _syncMetaBox = 'sync_meta';
  static const String _cursorKey = 'last_product_sync_at';
  static const Duration _pollInterval = Duration(seconds: 60);

  final SupabaseClient _client = SupabaseClientManager.client;
  final StreamController<CatalogConflictEvent> _conflicts =
      StreamController<CatalogConflictEvent>.broadcast();

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  StreamSubscription<bool>? _connectivitySub;
  bool _realtimeSubscribed = false;
  bool _isSyncing = false;

  /// Stream of cart-in-conflict signals for the UI to observe (§4.4).
  Stream<CatalogConflictEvent> get conflicts => _conflicts.stream;

  Box get _metaBox => Hive.box(_syncMetaBox);

  String? get cursor => _metaBox.get(_cursorKey) as String?;

  Future<void> _ensureBoxOpen() async {
    if (!Hive.isBoxOpen(_syncMetaBox)) {
      await Hive.openBox(_syncMetaBox);
    }
  }

  Future<void> _setCursor(String iso) => _metaBox.put(_cursorKey, iso);

  /// Full sync on first login (no cursor) or delta sync otherwise.
  /// Preserves the original `syncCatalog()` contract used by the auth flow.
  Future<void> syncCatalog() async {
    await _ensureBoxOpen();
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    if (businessId == null || branchId == null) {
      throw Exception('Business and branch must be selected before syncing');
    }

    final since = cursor;
    if (since == null) {
      await _fullSync(businessId, branchId);
      return;
    }
    await _deltaSync(businessId, branchId, since);
  }

  Future<void> _fullSync(String businessId, String branchId) async {
    final response = await _client.rpc(
      'get_branch_catalog',
      params: {'p_business_id': businessId, 'p_branch_id': branchId},
    ) as Map<String, dynamic>;

    final products = (response['products'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final inventory = (response['inventory'] as List<dynamic>)
        .cast<Map<String, dynamic>>();
    final invByProduct = {
      for (final i in inventory)
        i['product_id'] as String: (i['quantity'] as num?)?.toInt() ?? 0,
    };

    final productBox = HiveDatabase.productBox;
    await productBox.clear();

    String? maxUpdatedAt;
    for (final p in products) {
      final id = p['id'] as String;
      final qty = invByProduct[id] ?? 0;
      await productBox.put(
        id,
        ProductModel.fromSupabase(p, branchQuantity: qty),
      );
      final updated = p['updated_at'] as String?;
      if (updated != null &&
          (maxUpdatedAt == null || updated.compareTo(maxUpdatedAt) > 0)) {
        maxUpdatedAt = updated;
      }
    }
    if (maxUpdatedAt != null) {
      await _setCursor(maxUpdatedAt);
    }
  }

  Future<void> _deltaSync(
    String businessId,
    String branchId,
    String since,
  ) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final response = await _client.rpc(
        'get_catalog_delta',
        params: {
          'p_business_id': businessId,
          'p_branch_id': branchId,
          'p_since': since,
        },
      ) as Map<String, dynamic>;

      final products = (response['products'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final inventory = (response['inventory'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final invByProduct = {
        for (final i in inventory)
          i['product_id'] as String: (i['quantity'] as num?)?.toInt() ?? 0,
      };

      final productBox = HiveDatabase.productBox;
      String? maxUpdatedAt;

      for (final p in products) {
        final id = p['id'] as String;
        final deletedAt = p['deleted_at'] as String?;
        final updated = p['updated_at'] as String?;

        if (deletedAt != null) {
          if (productBox.containsKey(id)) {
            await productBox.delete(id);
            _conflicts.add(CatalogConflictEvent(id, CatalogConflictReason.deleted));
          }
        } else {
          final qty = invByProduct[id] ?? productBox.get(id)?.stock ?? 0;
          await productBox.put(
            id,
            ProductModel.fromSupabase(p, branchQuantity: qty),
          );
          _conflicts.add(
            CatalogConflictEvent(
              id,
              qty <= 0
                  ? CatalogConflictReason.outOfStock
                  : CatalogConflictReason.updated,
            ),
          );
        }
        if (updated != null &&
            (maxUpdatedAt == null || updated.compareTo(maxUpdatedAt) > 0)) {
          maxUpdatedAt = updated;
        }
      }

      // Inventory-only deltas (stock moved but product row unchanged).
      for (final entry in invByProduct.entries) {
        final id = entry.key;
        final qty = entry.value;
        final existing = productBox.get(id);
        if (existing == null || existing.stock == qty) continue;
        await productBox.put(
          id,
          ProductModel(
            id: existing.id,
            name: existing.name,
            barcode: existing.barcode,
            price: existing.price,
            stock: qty,
          ),
        );
        final invUpdated = inventory
            .firstWhere((i) => i['product_id'] as String == id)['updated_at'] as String?;
        if (invUpdated != null &&
            (maxUpdatedAt == null || invUpdated.compareTo(maxUpdatedAt) > 0)) {
          maxUpdatedAt = invUpdated;
        }
        _conflicts.add(
          CatalogConflictEvent(
            id,
            qty <= 0
                ? CatalogConflictReason.outOfStock
                : CatalogConflictReason.updated,
          ),
        );
      }

      if (maxUpdatedAt != null) {
        await _setCursor(maxUpdatedAt);
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Begins background sync: Realtime subscription when online, 60s polling
  /// fallback when Realtime is unavailable or the device is offline.
  void startBackgroundSync() {
    _ensureBoxOpen();
    _subscribeRealtime();
    _startPolling();
    _connectivitySub ??= Connectivity().onConnectivityChanged.map(
      (results) =>
          results.isNotEmpty && results.any((r) => r != ConnectivityResult.none),
    ).listen((isOnline) {
      if (isOnline) {
        _subscribeRealtime();
        syncCatalog();
      } else {
        _unsubscribeRealtime();
      }
    });
  }

  void stopBackgroundSync() {
    _unsubscribeRealtime();
    _stopPolling();
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  void _subscribeRealtime() {
    if (_realtimeSubscribed) return;
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    if (businessId == null || branchId == null) return;

    _channel = _client.channel('business:$businessId:branch:$branchId:catalog');

    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (payload) => _onRealtimeProduct(payload),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inventory',
          callback: (payload) => _onRealtimeInventory(payload),
        )
        .subscribe((status, _) {
      // Realtime dropped or errored — polling keeps data fresh.
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        _realtimeSubscribed = false;
        _startPolling();
      } else if (status == RealtimeSubscribeStatus.subscribed) {
        _realtimeSubscribed = true;
      }
    });
  }

  void _unsubscribeRealtime() {
    _channel?.unsubscribe();
    _channel = null;
    _realtimeSubscribed = false;
  }

  Future<void> _onRealtimeProduct(PostgresChangePayload payload) async {
    final record = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
    if (record.isEmpty) return;
    final id = record['id'] as String?;
    if (id == null) return;
    final deletedAt = record['deleted_at'] as String?;
    final productBox = HiveDatabase.productBox;
    if (deletedAt != null || payload.eventType == PostgresChangeEvent.delete) {
      if (productBox.containsKey(id)) {
        await productBox.delete(id);
        _conflicts.add(CatalogConflictEvent(id, CatalogConflictReason.deleted));
      }
      return;
    }
    final qty = productBox.get(id)?.stock ?? 0;
    await productBox.put(
      id,
      ProductModel.fromSupabase(record, branchQuantity: qty),
    );
    final updated = record['updated_at'] as String?;
    if (updated != null) {
      final cur = cursor;
      if (cur == null || updated.compareTo(cur) > 0) await _setCursor(updated);
    }
    _conflicts.add(CatalogConflictEvent(id, CatalogConflictReason.updated));
  }

  Future<void> _onRealtimeInventory(PostgresChangePayload payload) async {
    final record = payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord;
    if (record.isEmpty) return;
    final productId = record['product_id'] as String?;
    final qty = (record['quantity'] as num?)?.toInt();
    if (productId == null || qty == null) return;
    final productBox = HiveDatabase.productBox;
    final existing = productBox.get(productId);
    if (existing == null) return;
    await productBox.put(
      productId,
      ProductModel(
        id: existing.id,
        name: existing.name,
        barcode: existing.barcode,
        price: existing.price,
        stock: qty,
      ),
    );
    final updated = record['updated_at'] as String?;
    if (updated != null) {
      final cur = cursor;
      if (cur == null || updated.compareTo(cur) > 0) await _setCursor(updated);
    }
    _conflicts.add(
      CatalogConflictEvent(
        productId,
        qty <= 0
            ? CatalogConflictReason.outOfStock
            : CatalogConflictReason.updated,
      ),
    );
  }

  void _startPolling() {
    if (_pollTimer?.isActive ?? false) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) => syncCatalog());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void dispose() {
    stopBackgroundSync();
    _conflicts.close();
  }
}
