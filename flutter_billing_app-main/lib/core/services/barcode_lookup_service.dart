import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client.dart';
import 'barcode_lookup_result.dart';

/// Looks up product details for a scanned barcode.
///
/// First consults the local Supabase `barcode_cache` table. On a miss it
/// falls back to the free Open Food Facts API, caching any hit so subsequent
/// lookups for the same barcode are served locally.
class BarcodeLookupService {
  static const _openFoodFactsHost = 'world.openfoodfacts.org';
  static const _cacheTable = 'barcode_cache';

  final SupabaseClient _client;

  BarcodeLookupService({SupabaseClient? client})
      : _client = client ?? SupabaseClientManager.client;

  /// Returns product metadata for [barcode], or `null` when the barcode is
  /// unknown to both the local cache and Open Food Facts. Network errors are
  /// swallowed and result in `null` rather than throwing.
  Future<BarcodeLookupResult?> lookup(String barcode) async {
    final normalized = barcode.trim();
    if (normalized.isEmpty) return null;

    final cached = await _lookupCache(normalized);
    if (cached != null) return cached;

    final remote = await _lookupOpenFoodFacts(normalized);
    if (remote != null) {
      // Best-effort cache write; failures here must not break the lookup.
      await _cacheResult(normalized, remote).catchError((_) {});
    }
    return remote;
  }

  Future<BarcodeLookupResult?> _lookupCache(String barcode) async {
    try {
      final rows = await _client
          .from(_cacheTable)
          .select()
          .eq('barcode', barcode)
          .limit(1);
      if (rows.isEmpty) return null;
      final row = rows.first;
      final name = row['name'] as String?;
      if (name == null || name.isEmpty) return null;
      return BarcodeLookupResult(
        name: name,
        category: row['category'] as String?,
        brand: row['brand'] as String?,
        imageUrl: row['image_url'] as String?,
        suggestedPrice: (row['suggested_price'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<BarcodeLookupResult?> _lookupOpenFoodFacts(String barcode) async {
    final uri = Uri.https(
      _openFoodFactsHost,
      '/api/v2/product/$barcode.json',
    );
    final request = await HttpClient()
        .getUrl(uri)
        .timeout(const Duration(seconds: 10));
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode != HttpStatus.ok) return null;

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final status = json['status']?.toString();
    if (status != '1') return null;

    final product = json['product'] as Map<String, dynamic>?;
    if (product == null) return null;

    final name = (product['product_name'] as String?)?.trim().isNotEmpty == true
        ? product['product_name'] as String
        : product['product_name_en'] as String?;
    if (name == null || name.trim().isEmpty) return null;

    final categoriesRaw = product['categories'] as String? ?? '';
    final category = categoriesRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .firstOrNull;

    final brand = (product['brands'] as String?)
        ?.split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .firstOrNull;

    final imageUrl =
        (product['image_front_url'] as String?)?.isNotEmpty == true
            ? product['image_front_url'] as String
            : product['image_url'] as String?;

    return BarcodeLookupResult(
      name: name.trim(),
      category: category,
      brand: brand,
      imageUrl: (imageUrl?.isNotEmpty == true) ? imageUrl : null,
    );
  }

  Future<void> _cacheResult(String barcode, BarcodeLookupResult result) async {
    await _client.from(_cacheTable).insert({
      'barcode': barcode,
      'name': result.name,
      'category': result.category,
      'brand': result.brand,
      'image_url': result.imageUrl,
      'source': 'open_food_facts',
    });
  }
}
