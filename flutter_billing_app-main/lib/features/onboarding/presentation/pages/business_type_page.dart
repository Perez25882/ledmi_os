import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/onboarding_bloc.dart';
import '../../data/services/onboarding_service.dart';

/// Maps a business_types.icon string (stored in Supabase) to a Material Icon.
IconData _iconForName(String? name) {
  switch (name) {
    case 'store':
    case 'supermarket':
      return Icons.storefront;
    case 'local_pharmacy':
    case 'pharmacy':
      return Icons.local_pharmacy;
    case 'devices':
    case 'electronics':
      return Icons.devices;
    case 'checkroom':
    case 'fashion':
      return Icons.checkroom;
    case 'hardware':
    case 'build':
      return Icons.build;
    case 'category':
    case 'other':
      return Icons.category;
    default:
      return Icons.store_mall_directory;
  }
}

class BusinessTypePage extends StatefulWidget {
  const BusinessTypePage({super.key});

  @override
  State<BusinessTypePage> createState() => _BusinessTypePageState();
}

class _BusinessTypePageState extends State<BusinessTypePage> {
  @override
  void initState() {
    super.initState();
    context.read<OnboardingBloc>().add(LoadBusinessTypes());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(
                top: 40,
                left: 24,
                right: 24,
                bottom: 24,
              ),
              decoration: const BoxDecoration(color: AppTheme.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryForeground.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'L',
                            style: TextStyle(
                              color: AppTheme.primaryForeground,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Welcome to LedgerMind',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primaryForeground,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Let's set up your store. First, what type of business do you run?",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.primaryForeground,
                    ),
                  ),
                ],
              ),
            ),
            // Step indicator
            Padding(
              padding: const EdgeInsets.only(top: 16, left: 24, right: 24),
              child: Row(
                children: [
                  _stepDot(true),
                  _stepLine(false),
                  _stepDot(false),
                  _stepLine(false),
                  _stepDot(false),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Content
            Expanded(
              child: BlocBuilder<OnboardingBloc, OnboardingState>(
                builder: (context, state) {
                  if (state.status == OnboardingStatus.loading &&
                      state.businessTypes.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    );
                  }
                  if (state.status == OnboardingStatus.error &&
                      state.businessTypes.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline,
                                size: 48, color: AppTheme.destructive),
                            const SizedBox(height: 12),
                            Text(
                              state.error ?? 'Failed to load business types',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.destructive,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () => context
                                  .read<OnboardingBloc>()
                                  .add(LoadBusinessTypes()),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return _buildGrid(state);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(OnboardingState state) {
    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.0,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: state.businessTypes.length,
      itemBuilder: (context, index) {
        final type = state.businessTypes[index];
        final isSelected = state.status == OnboardingStatus.loading &&
            state.selectedBusinessTypeId == type.id;
        return _BusinessTypeCard(
          type: type,
          isSelected: isSelected,
          onTap: () {
            context.read<OnboardingBloc>().add(SelectBusinessType(
                  businessTypeId: type.id,
                  businessTypeName: type.name,
                ));
          },
        );
      },
    );
  }

  Widget _stepDot(bool active) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: active ? AppTheme.primary : AppTheme.muted,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          active ? '1' : '•',
          style: TextStyle(
            color: active
                ? AppTheme.primaryForeground
                : AppTheme.mutedForeground,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _stepLine(bool active) {
    return Expanded(
      child: Container(
        height: 3,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: active ? AppTheme.primary : AppTheme.border,
      ),
    );
  }
}

class _BusinessTypeCard extends StatelessWidget {
  final BusinessType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _BusinessTypeCard({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppTheme.primary : AppTheme.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                _iconForName(type.icon),
                size: 32,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              type.name,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.foreground,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _subtitleForType(type.id),
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.mutedForeground,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _subtitleForType(String id) {
    switch (id) {
      case 'supermarket':
        return 'Groceries & daily goods';
      case 'pharmacy':
        return 'Medicine & health';
      case 'electronics':
        return 'Phones & gadgets';
      case 'fashion':
        return 'Clothing & apparel';
      case 'hardware':
        return 'Tools & supplies';
      default:
        return 'Custom setup';
    }
  }
}
