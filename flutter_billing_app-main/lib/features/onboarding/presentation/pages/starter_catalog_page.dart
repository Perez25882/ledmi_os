import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/onboarding_bloc.dart';
import '../../data/services/onboarding_service.dart';

class StarterCatalogPage extends StatefulWidget {
  const StarterCatalogPage({super.key});

  @override
  State<StarterCatalogPage> createState() => _StarterCatalogPageState();
}

class _StarterCatalogPageState extends State<StarterCatalogPage> {
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
                  const Text(
                    'Starter Catalog',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryForeground,
                    ),
                  ),
                  const SizedBox(height: 6),
                  BlocBuilder<OnboardingBloc, OnboardingState>(
                    builder: (context, state) {
                      final count = state.selectedTemplates.length;
                      final typeName = state.selectedBusinessTypeName ?? '';
                      return Text(
                        "We've prepared $count products for your $typeName business",
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.primaryForeground,
                        ),
                      );
                    },
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
                  _stepLine(true),
                  _stepDot(true),
                  _stepLine(false),
                  _stepDot(false),
                ],
              ),
            ),
            const SizedBox(height: 4),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Toggle off any items you don\'t sell',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.mutedForeground,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Product list
            Expanded(
              child: BlocBuilder<OnboardingBloc, OnboardingState>(
                builder: (context, state) {
                  if (state.status == OnboardingStatus.loading &&
                      state.catalogTemplates.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    );
                  }
                  if (state.status == OnboardingStatus.error &&
                      state.catalogTemplates.isEmpty) {
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
                              state.error ?? 'Failed to load catalog',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTheme.destructive,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (state.catalogTemplates.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.inventory_2_outlined,
                              size: 48, color: AppTheme.mutedForeground),
                          const SizedBox(height: 12),
                          const Text(
                            'No starter products for this business type.',
                            style: TextStyle(
                              color: AppTheme.mutedForeground,
                            ),
                          ),
                          const SizedBox(height: 24),
                          _continueButton(context, enabled: true),
                        ],
                      ),
                    );
                  }
                  return Column(
                    children: [
                      Expanded(child: _buildList(state)),
                      _buildFooter(context, state),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(OnboardingState state) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: state.catalogTemplates.length,
      itemBuilder: (context, index) {
        final template = state.catalogTemplates[index];
        final isSelected = !state.deselectedTemplateIds.contains(template.id);
        return _CatalogTile(
          template: template,
          isSelected: isSelected,
          onToggle: () => context
              .read<OnboardingBloc>()
              .add(ToggleTemplateSelection(template.id)),
        );
      },
    );
  }

  Widget _buildFooter(BuildContext context, OnboardingState state) {
    final selectedCount = state.selectedTemplates.length;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppTheme.card,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.status == OnboardingStatus.error &&
              state.catalogTemplates.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                state.error ?? '',
                style: const TextStyle(color: AppTheme.destructive, fontSize: 13),
              ),
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$selectedCount selected',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.foreground,
                ),
              ),
              _continueButton(context, enabled: selectedCount > 0),
            ],
          ),
        ],
      ),
    );
  }

  Widget _continueButton(BuildContext context, {required bool enabled}) {
    return BlocBuilder<OnboardingBloc, OnboardingState>(
      builder: (context, state) {
        final isLoading = state.status == OnboardingStatus.loading &&
            state.catalogTemplates.isNotEmpty;
        return ElevatedButton(
          onPressed: (enabled && !isLoading)
              ? () => context.read<OnboardingBloc>().add(ConfirmStarterCatalog())
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.primary,
            foregroundColor: AppTheme.primaryForeground,
            disabledBackgroundColor: AppTheme.muted,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppTheme.primaryForeground,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'Continue',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
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
          active ? '2' : '•',
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

class _CatalogTile extends StatelessWidget {
  final StarterCatalogTemplate template;
  final bool isSelected;
  final VoidCallback onToggle;

  const _CatalogTile({
    required this.template,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: isSelected ? AppTheme.card : AppTheme.muted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected ? AppTheme.primary : AppTheme.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      elevation: 0,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              // Checkbox
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: isSelected ? AppTheme.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppTheme.primary : AppTheme.border,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: isSelected
                    ? const Icon(Icons.check,
                        size: 16, color: AppTheme.primaryForeground)
                    : null,
              ),
              const SizedBox(width: 12),
              // Product info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppTheme.foreground
                            : AppTheme.mutedForeground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      template.category,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
              // Price
              Text(
                'GHS ${template.suggestedPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? AppTheme.primary : AppTheme.mutedForeground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
