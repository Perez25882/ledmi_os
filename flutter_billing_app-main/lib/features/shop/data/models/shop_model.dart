// ignore_for_file: overridden_fields

import 'package:hive/hive.dart';
import '../../domain/entities/shop.dart';

part 'shop_model.g.dart';

@HiveType(typeId: 1)
class ShopModel extends Shop {
  @override
  @HiveField(0)
  final String name;
  @override
  @HiveField(1)
  final String addressLine1;
  @override
  @HiveField(2)
  final String addressLine2;
  @override
  @HiveField(3)
  final String phoneNumber;
  @override
  @HiveField(4)
  final String upiId;
  @override
  @HiveField(5)
  final String footerText;

  const ShopModel({
    required this.name,
    required this.addressLine1,
    required this.addressLine2,
    required this.phoneNumber,
    required this.upiId,
    required this.footerText,
  }) : super(
          name: name,
          addressLine1: addressLine1,
          addressLine2: addressLine2,
          phoneNumber: phoneNumber,
          upiId: upiId,
          footerText: footerText,
        );

  factory ShopModel.fromEntity(Shop shop) {
    return ShopModel(
      name: shop.name,
      addressLine1: shop.addressLine1,
      addressLine2: shop.addressLine2,
      phoneNumber: shop.phoneNumber,
      upiId: shop.upiId,
      footerText: shop.footerText,
    );
  }

  /// Builds a [ShopModel] from a `branches` row joined with its parent
  /// `businesses` row. Used by [ShopRepositoryImpl] when reading from
  /// Supabase. Tolerates missing columns/NULLs so a partially-populated
  /// branch still loads.
  factory ShopModel.fromSupabase(Map<String, dynamic> branch,
      [Map<String, dynamic>? business]) {
    final businessName = (business?['name'] as String?) ?? '';
    final branchName = (branch['name'] as String?) ?? '';
    final name = businessName.isEmpty
        ? branchName
        : (branchName.isEmpty ? businessName : '$businessName - $branchName');

    return ShopModel(
      name: name,
      addressLine1: (branch['location'] as String?) ?? '',
      addressLine2: '',
      phoneNumber: (branch['phone'] as String?) ?? '',
      upiId: (branch['momo_number'] as String?) ?? '',
      footerText: (branch['footer_text'] as String?) ?? '',
    );
  }

  /// Payload for `branches` UPDATE. Only the columns owned by `branches`
  /// are included; `name` is the branch name, not the composite display
  /// name, so callers that loaded a composite name should set it
  /// explicitly before calling [updateShop].
  Map<String, dynamic> toSupabaseBranch() => {
        'location': addressLine1,
        'phone': phoneNumber,
        'momo_number': upiId,
        'footer_text': footerText,
      };

  Shop toEntity() => this;
}
