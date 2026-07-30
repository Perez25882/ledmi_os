import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/quick_sale_suggestion.dart';
import '../bloc/billing_bloc.dart';
import 'quick_sale_add_to_catalog_dialog.dart';

/// A banner displayed at the top of the home page when there are quick sale
/// items that have been sold frequently and could be promoted to the catalog.
///
/// Shows one suggestion at a time (the top suggestion by times sold). The
/// cashier can:
/// * tap **Yes** to open the add-to-catalog bottom sheet,
/// * tap **Later** to dismiss for today, or
/// * tap **Never** to permanently denylist the suggestion.
class QuickSaleSuggestionBanner extends StatelessWidget {
  const QuickSaleSuggestionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BillingBloc, BillingState>(
      buildWhen: (prev, curr) =>
          prev.quickSaleSuggestions != curr.quickSaleSuggestions ||
          prev.isProcessing != curr.isProcessing,
      builder: (context, state) {
        if (state.quickSaleSuggestions.isEmpty) {
          return const SizedBox.shrink();
        }
        final suggestion = state.quickSaleSuggestions.first;
        return _SuggestionCard(suggestion: suggestion);
      },
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final QuickSaleSuggestion suggestion;

  const _SuggestionCard({required this.suggestion});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.lightbulb_outline,
                color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You\'ve sold "${suggestion.name}" as a quick sale '
                  '${suggestion.timesSold} times this week.',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.foreground,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Avg price: GHS ${suggestion.avgPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.mutedForeground,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _actionChip(
                      label: 'Yes',
                      primary: true,
                      onTap: () =>
                          _showAddToCatalog(context, suggestion),
                    ),
                    _actionChip(
                      label: 'Later',
                      onTap: () => context.read<BillingBloc>().add(
                            DismissQuickSaleSuggestionEvent(
                                suggestion.name, false),
                          ),
                    ),
                    _actionChip(
                      label: 'Never',
                      onTap: () => context.read<BillingBloc>().add(
                            DismissQuickSaleSuggestionEvent(
                                suggestion.name, true),
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: primary ? AppTheme.primary : AppTheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: primary
                ? AppTheme.primary
                : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: primary ? AppTheme.primaryForeground : AppTheme.foreground,
          ),
        ),
      ),
    );
  }

  Future<void> _showAddToCatalog(
      BuildContext context, QuickSaleSuggestion suggestion) async {
    final result = await showQuickSaleAddToCatalogDialog(
      context,
      name: suggestion.name,
      avgPrice: suggestion.avgPrice,
    );
    if (result == null || !context.mounted) return;
    context.read<BillingBloc>().add(AddQuickSaleToCatalogEvent(
          result.name,
          result.price,
          result.category,
        ));
  }
}
