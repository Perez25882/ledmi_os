import 'package:billing_app/core/widgets/input_label.dart';
import 'package:billing_app/core/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../domain/entities/shop.dart';
import '../bloc/shop_bloc.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_validators.dart';

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
  String? get _branchId => SessionManager.branchId;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Shop Details'),
        ),
        body: Column(
          children: [
            if (_branchId != null)
              Container(
                width: double.infinity,
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.store,
                        size: 16, color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Branch: $_branchId',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!_canEdit)
                      Text('Read-only',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w600,
                          )),
                  ],
                ),
              ),
            Expanded(
              child: BlocConsumer<ShopBloc, ShopState>(
          listener: (context, state) {
            if (state is ShopLoaded) {
              _updateControllers(state.shop);
            } else if (state is ShopOperationSuccess) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Shop details saved!'),
                  backgroundColor: Colors.green));
              context.pop();
            } else if (state is ShopError) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(state.message), backgroundColor: Colors.red));
            }
          },
          buildWhen: (previous, current) =>
              current is ShopLoading || current is ShopLoaded,
          builder: (context, state) {
            if (state is ShopLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('General Information',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: AppTheme.primaryColor.withValues(alpha: 0.8),
                        )),
                    const SizedBox(
                      height: 5,
                    ),
                    Text(
                      'These details will appear on your digital and printed receipts.',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    const SizedBox(height: 24),
                    const InputLabel(text: 'Shop Name'),
                    _buildTextField(
                      controller: _nameController,
                      hint: 'e.g. AmaMart Supermarket',
                      validator: AppValidators.required('Required'),
                    ),
                    const SizedBox(height: 15),
                    const InputLabel(text: 'Address Line 1'),
                    _buildTextField(
                      controller: _address1Controller,
                      hint: 'Oxford Street, Osu',
                      validator: AppValidators.required('Required'),
                    ),
                    const SizedBox(height: 15),
                    const InputLabel(text: 'Address Line 2 (Optional)'),
                    _buildTextField(
                      controller: _address2Controller,
                      hint: 'Accra - GA-123-4567',
                    ),
                    const SizedBox(height: 15),
                    const InputLabel(text: 'Phone Number'),
                    _buildTextField(
                      controller: _phoneController,
                      hint: '+233 24 123 4567',
                      keyboardType: TextInputType.phone,
                      validator: AppValidators.required('Required'),
                    ),
                    const SizedBox(height: 15),
                    const InputLabel(text: 'MoMo Number'),
                    _buildTextField(
                      controller: _momoController,
                      hint: 'e.g. MTN 024 123 4567',
                      keyboardType: TextInputType.phone,
                    ),
                    Text('Provider: MTN / Vodafone / AirtelTigo',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey[400])),
                    const SizedBox(height: 15),
                    const InputLabel(text: 'GRA TIN (Optional)'),
                    _buildTextField(
                      controller: _tinController,
                      hint: 'e.g. P123456789Z',
                    ),
                    const SizedBox(height: 15),
                    const InputLabel(text: 'Business Registration (Optional)'),
                    _buildTextField(
                      controller: _registrationController,
                      hint: 'e.g. Registrar General\'s Dept. No.',
                    ),
                    const SizedBox(height: 15),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const InputLabel(text: 'Receipt Footer Text'),
                        Text('Max 150 chars',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[400])),
                      ],
                    ),
                    _buildTextField(
                      controller: _footerController,
                      hint: 'Thank you, Visit again!!!',
                      maxLines: 2,
                      maxLength: 60,
                    ),
                  ],
                ),
              ),
            );
          },
            ),
            ),
          ],
        ),
        bottomNavigationBar: _canEdit
            ? PrimaryButton(
                onPressed: _saveShop,
                icon: Icons.save,
                label: 'Save Details',
              )
            : const SizedBox(height: 0),
      );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      maxLength: maxLength,
      textCapitalization: TextCapitalization.words,
      validator: validator,
      readOnly: !_canEdit,
      decoration: InputDecoration(
        hintText: hint,
        filled: !_canEdit,
        fillColor: Colors.grey[100],
      ),
    );
  }
}
