import 'delta_sync_client.dart';

/// Catalog sync facade preserved for existing callers (auth flow, DI).
///
/// Delta sync, Realtime subscription, polling fallback, and cart-in-conflict
/// signals are implemented in [DeltaSyncClient] per SYNC_PROTOCOL §4.3/§4.4.
class SupabaseSyncService {
  final DeltaSyncClient _delta = DeltaSyncClient();

  /// Full sync on first login (no cursor), delta sync otherwise.
  Future<void> syncCatalog() => _delta.syncCatalog();

  /// Realtime + 60s polling fallback. Call once the session is established.
  void startBackgroundSync() => _delta.startBackgroundSync();

  void stopBackgroundSync() => _delta.stopBackgroundSync();

  /// Cart-in-conflict signal stream (§4.4). The billing layer should listen
  /// and cross-reference affected product ids against the active cart.
  Stream<CatalogConflictEvent> get conflicts => _delta.conflicts;
}
