/// Result of a barcode lookup against the local cache or a global database.
class BarcodeLookupResult {
  final String name;
  final String? category;
  final String? brand;
  final String? imageUrl;
  final double? suggestedPrice;

  const BarcodeLookupResult({
    required this.name,
    this.category,
    this.brand,
    this.imageUrl,
    this.suggestedPrice,
  });

  @override
  String toString() =>
      'BarcodeLookupResult(name: $name, category: $category, brand: $brand, '
      'imageUrl: $imageUrl, suggestedPrice: $suggestedPrice)';
}
