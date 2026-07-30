import 'package:fpdart/fpdart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/data/hive_database.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../domain/entities/shop.dart';
import '../../domain/repositories/shop_repository.dart';
import '../models/shop_model.dart';

/// Supabase-backed shop repository with offline Hive cache.
///
/// Source of truth is the `branches` row for the cashier's active branch
/// (joined with `businesses` for the business name). When the device is
/// offline or the fetch fails, the last successfully cached [ShopModel]
/// is returned from Hive so the POS can still render the Shop Details
/// screen. Writes go to Supabase and update the cache on success.
class ShopRepositoryImpl implements ShopRepository {
  static const String shopKey = 'shop_details';

  SupabaseClient get _client => SupabaseClientManager.client;

  @override
  Future<Either<Failure, Shop>> getShop() async {
    final branchId = SessionManager.branchId;
    final businessId = SessionManager.businessId;

    // Try Supabase first when we have a branch context.
    if (branchId != null && businessId != null) {
      try {
        final row = await _client
            .from('branches')
            .select('*, businesses(name, currency)')
            .eq('id', branchId)
            .maybeSingle();

        if (row != null) {
          final branch = Map<String, dynamic>.from(row);
          final business =
              (branch.remove('businesses') as Map<String, dynamic>?) ??
                  <String, dynamic>{};
          final model = ShopModel.fromSupabase(branch, business);
          await _cache(model);
          return Right(model);
        }
      } on PostgrestException catch (_) {
        // Fall through to cache.
      } catch (_) {
        // Fall through to cache.
      }
    }

    // Fallback: Hive cache (or default if never cached).
    return _fromCache();
  }

  @override
  Future<Either<Failure, void>> updateShop(Shop shop) async {
    final branchId = SessionManager.branchId;
    if (branchId == null) {
      // No branch context — persist locally only.
      return _cacheOnly(shop);
    }

    try {
      final model = ShopModel.fromEntity(shop);
      await _client
          .from('branches')
          .update(model.toSupabaseBranch())
          .eq('id', branchId);
      await _cache(model);
      return const Right(null);
    } on PostgrestException catch (e) {
      // Persist locally so the next load shows the intended values
      // even if the write failed (e.g. RLS denial or offline).
      await _cache(ShopModel.fromEntity(shop));
      return Left(ServerFailure(e.message));
    } catch (e) {
      await _cache(ShopModel.fromEntity(shop));
      return Left(ServerFailure(e.toString()));
    }
  }

  Future<Either<Failure, Shop>> _fromCache() async {
    try {
      final box = HiveDatabase.shopBox;
      final cached = box.get(shopKey);
      if (cached != null) return Right(cached);
      // Default shop if never cached and Supabase unavailable.
      return const Right(Shop(
        name: 'My Shop',
        addressLine1: '',
        addressLine2: '',
        phoneNumber: '',
        upiId: '',
        footerText: 'Thank you, Visit again!!!',
      ));
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  Future<Either<Failure, void>> _cacheOnly(Shop shop) async {
    try {
      await HiveDatabase.shopBox.put(shopKey, ShopModel.fromEntity(shop));
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure(e.toString()));
    }
  }

  Future<void> _cache(ShopModel model) async {
    try {
      await HiveDatabase.shopBox.put(shopKey, model);
    } catch (_) {
      // Cache failures are non-fatal; Supabase is source of truth.
    }
  }
}
