import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/shop.dart';
import '../bloc/shop_bloc.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../../../core/theme/app_theme.dart';

class ShopDetailsPage extends StatefulWidget {
  const ShopDetailsPage({super.key});

  @override
  State<ShopDetailsPage> createState() => _ShopDetailsPageState();
}

class _ShopDetailsPageState extends State<ShopDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _address1Controller;
  late TextEditingController _address2Controller;
  late TextEditingController _phoneController;
  late TextEditingController _momoController;
  late TextEditingController _tinController;
  late TextEditingController _registrationController;
  late TextEditingController _footerController;

  final bool _canEdit = SessionManager.canManageBusiness;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _address1Controller = TextEditingController();
    _address2Controller = TextEditingController();
    _phoneController = TextEditingController();
    _momoController = TextEditingController();
    _tinController = TextEditingController();
    _registrationController = TextEditingController();
    _footerController = TextEditingController();

    context.read<ShopBloc>().add(LoadShopEvent());
  }

  void _updateControllers(Shop shop) {
    if (_nameController.text.isEmpty && shop.name.isNotEmpty) {
      _nameController.text = shop.name;
      _address1Controller.text = shop.addressLine1;
      _address2Controller.text = shop.addressLine2;
      _phoneController.text = shop.phoneNumber;
      _momoController.text = shop.upiId;
      _footerController.text = shop.footerText;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _phoneController.dispose();
    _momoController.dispose();
    _tinController.dispose();
    _registrationController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  void _saveShop() {
    if (_formKey.currentState!.validate()) {
      final shop = Shop(
        name: _nameController.text,
        addressLine1: _address1Controller.text,
        addressLine2: _address2Controller.text,
        phoneNumber: _phoneController.text,
        upiId: _momoController.text,
        footerText: _footerController.text,
      );

      context.read<ShopBloc>().add(UpdateShopEvent(shop));
    }
  }

  void _openEditSheet(Shop shop) {
    // Seed controllers with current values so the sheet shows live data.
    _nameController.text = shop.name;
    _address1Controller.text = shop.addressLine1;
    _address2Controller.text = shop.addressLine2;
    _phoneController.text = shop.phoneNumber;
    _momoController.text = shop.upiId;
    _footerController.text = shop.footerText;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Text('Edit Shop Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.foreground,
                    )),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Shop Name'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address1Controller,
                  decoration:
                      const InputDecoration(labelText: 'Address Line 1'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _address2Controller,
                  decoration: const InputDecoration(
                      labelText: 'Address Line 2 (Optional)'),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  decoration:
                      const InputDecoration(labelText: 'Phone Number'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _momoController,
                  decoration: const InputDecoration(
                      labelText: 'MoMo Number',
                      hintText: 'e.g. MTN 024 123 4567'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _footerController,
                  decoration: const InputDecoration(
                      labelText: 'Receipt Footer Text'),
                  maxLength: 60,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _saveShop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.primaryForeground,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Save Changes',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: BlocConsumer<ShopBloc, ShopState>(
        listener: (context, state) {
          if (state is ShopLoaded) {
            _updateControllers(state.shop);
          } else if (state is ShopOperationSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Shop details saved!'),
                backgroundColor: AppTheme.success));
            context.pop();
          } else if (state is ShopError) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(state.message),
                backgroundColor: AppTheme.destructive));
          }
        },
        buildWhen: (previous, current) =>
            current is ShopLoading || current is ShopLoaded,
        builder: (context, state) {
          if (state is ShopLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final shop = state is ShopLoaded ? state.shop : null;
          final name = shop?.name.isNotEmpty == true ? shop!.name : 'My Shop';
          final address = [
            shop?.addressLine1 ?? '',
            shop?.addressLine2 ?? ''
          ].where((s) => s.isNotEmpty).join(', ');
          final phone = shop?.phoneNumber ?? '';
          final momo = shop?.upiId ?? '';
          final initial = name.isNotEmpty ? name[0].toUpperCase() : 'S';

          return CustomScrollView(
            slivers: [
              // Teal header
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                backgroundColor: AppTheme.primary,
                foregroundColor: AppTheme.primaryForeground,
                leading: IconButton(
                  icon: const Icon(Icons.chevron_left, size: 28),
                  onPressed: () => context.pop(),
                ),
                title: const Text(
                  'Shop Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: true,
                flexibleSpace: const FlexibleSpaceBar(
                  background: ColoredBox(
                    color: AppTheme.primary,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Image band
                    Container(
                      height: 120,
                      color: AppTheme.accent,
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Name card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.foreground,
                                          )),
                                      const SizedBox(height: 4),
                                      Text(
                                        address.isNotEmpty
                                            ? address
                                            : 'No address set',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: AppTheme.mutedForeground,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.success,
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: const Text(
                                    'Open',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryForeground,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Stats row
                          Row(
                            children: [
                              _buildStatCard(
                                  'Today Sales', 'GHS 2,450', true),
                              const SizedBox(width: 8),
                              _buildStatCard('Transactions', '47', false),
                              const SizedBox(width: 8),
                              _buildStatCard('Items Sold', '128', false),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // Info section
                          const Padding(
                            padding: EdgeInsets.only(left: 8, bottom: 8),
                            child: Text(
                              'SHOP INFORMATION',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.mutedForeground,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppTheme.border),
                            ),
                            child: Column(
                              children: [
                                _buildInfoRow('Phone',
                                    phone.isNotEmpty ? phone : '+233 —'),
                                const Divider(
                                    height: 1,
                                    color: AppTheme.border,
                                    indent: 16,
                                    endIndent: 16),
                                _buildInfoRow('Email', 'osacc@ledgermind.gh'),
                                const Divider(
                                    height: 1,
                                    color: AppTheme.border,
                                    indent: 16,
                                    endIndent: 16),
                                _buildInfoRow(
                                    'Opening Hours', '8:00 AM - 9:00 PM'),
                                const Divider(
                                    height: 1,
                                    color: AppTheme.border,
                                    indent: 16,
                                    endIndent: 16),
                                _buildInfoRow(
                                    'Tax ID', 'GRA-001234567'),
                                const Divider(
                                    height: 1,
                                    color: AppTheme.border,
                                    indent: 16,
                                    endIndent: 16),
                                _buildInfoRow(
                                    'MoMo Number',
                                    momo.isNotEmpty ? momo : 'Not set'),
                                const Divider(
                                    height: 1,
                                    color: AppTheme.border,
                                    indent: 16,
                                    endIndent: 16),
                                _buildInfoRow(
                                    'Currency', 'GHS (Ghana Cedi)'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          // Edit button
                          if (_canEdit)
                            SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: shop == null ? null : () => _openEditSheet(shop),
                                icon: const Icon(Icons.edit_outlined, size: 18),
                                label: const Text(
                                  'Edit Shop Details',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primary,
                                  foregroundColor: AppTheme.primaryForeground,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTheme.muted,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Read-only: only owners and managers can edit shop details.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.mutedForeground,
                                ),
                              ),
                            ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, bool highlight) {
    return Expanded(
      child: Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.mutedForeground,
                )),
            Text(value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: highlight ? AppTheme.primary : AppTheme.foreground,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.foreground,
              )),
          Text(value,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.mutedForeground,
              )),
        ],
      ),
    );
  }
}
