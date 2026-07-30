import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/stock_prediction.dart';
import '../bloc/owner_bloc.dart';

class LowStockPage extends StatefulWidget {
  const LowStockPage({super.key});

  @override
  State<LowStockPage> createState() => _LowStockPageState();
}

class _LowStockPageState extends State<LowStockPage> {
  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadStockPredictions());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Low Stock Predictions')),
      body: BlocListener<OwnerBloc, OwnerState>(
        listenWhen: (prev, curr) =>
            prev.successMessage != curr.successMessage ||
            prev.error != curr.error,
        listener: (context, state) {
          if (state.successMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.successMessage!),
                backgroundColor: AppTheme.success,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: AppTheme.destructive,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: BlocBuilder<OwnerBloc, OwnerState>(
          builder: (context, state) {
            if (state.isLoading && state.stockPredictions.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            if (state.stockPredictions.isEmpty) {
              return _buildEmptyView(context);
            }
            final predictions = state.stockPredictions;
            final critical = predictions
                .where((p) => p.urgency == PredictionUrgency.critical)
                .length;
            final warning = predictions
                .where((p) => p.urgency == PredictionUrgency.warning)
                .length;
            final info = predictions
                .where((p) => p.urgency == PredictionUrgency.info)
                .length;

            return RefreshIndicator(
              onRefresh: () async {
                context.read<OwnerBloc>().add(LoadStockPredictions());
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: predictions.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return _buildSummary(
                        context, critical, warning, info, state.isLoading);
                  }
                  final prediction = predictions[index - 1];
                  return _buildPredictionCard(
                      context, prediction, state.isLoading);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyView(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppTheme.success, size: 64),
          const SizedBox(height: 16),
          Text('All stock levels are healthy',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  )),
          const SizedBox(height: 4),
          Text('No products predicted to run out soon',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.mutedForeground,
                  )),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, int critical, int warning,
      int info, bool isLoading) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: _buildSummaryChip(
                context,
                '$critical',
                'Critical',
                AppTheme.destructive,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryChip(
                context,
                '$warning',
                'Warning',
                AppTheme.warning,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildSummaryChip(
                context,
                '$info',
                'Info',
                AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryChip(
      BuildContext context, String count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(count,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: color,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.mutedForeground,
                    fontSize: 11,
                  )),
        ],
      ),
    );
  }

  Widget _buildPredictionCard(
      BuildContext context, StockPrediction prediction, bool isLoading) {
    final color = _urgencyColor(prediction.urgency);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(prediction.name,
                      style:
                          Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              )),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${prediction.currentStock} left',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 16, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _stockoutText(prediction),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.shopping_cart_outlined,
                    size: 16, color: AppTheme.mutedForeground),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Suggested reorder: ${prediction.suggestedReorder} units '
                    '(${prediction.dailyVelocity.toStringAsFixed(1)}/day)',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.mutedForeground,
                        ),
                  ),
                ),
              ],
            ),
            if (prediction.lastSoldHoursAgo != null) ...[
              const SizedBox(height: 4),
              Text(
                'Last sold: ${_formatHoursAgo(prediction.lastSoldHoursAgo!)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.mutedForeground,
                    ),
              ),
            ],
            if (prediction.aiInsight != null &&
                prediction.aiInsight!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 16, color: AppTheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        prediction.aiInsight!,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.foreground,
                                  fontStyle: FontStyle.italic,
                                ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isLoading
                        ? null
                        : () => _recordStockIn(context, prediction),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Record Stock-In'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: AppTheme.primaryForeground,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: isLoading
                      ? null
                      : () {
                          context.read<OwnerBloc>().add(DismissStockAlert(
                                productId: prediction.productId,
                                productName: prediction.name,
                              ));
                        },
                  child: const Text('Dismiss',
                      style:
                          TextStyle(color: AppTheme.mutedForeground)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _recordStockIn(BuildContext context, StockPrediction prediction) {
    context.push('/manage/stock-in', extra: {
      'id': prediction.productId,
      'name': prediction.name,
      'barcode': '',
      'selling_price': 0,
      'cost_price': 0,
    });
  }

  Color _urgencyColor(PredictionUrgency urgency) {
    switch (urgency) {
      case PredictionUrgency.critical:
        return AppTheme.destructive;
      case PredictionUrgency.warning:
        return AppTheme.warning;
      case PredictionUrgency.info:
        return AppTheme.primary;
    }
  }

  String _stockoutText(StockPrediction prediction) {
    final days = prediction.daysUntilStockout;
    if (days == null) {
      return prediction.dailyVelocity > 0
          ? 'Stockout predicted soon'
          : 'No recent sales — stockout risk unknown';
    }
    if (days < 1) {
      final hours = (days * 24).round();
      if (hours <= 0) {
        return 'Stockout predicted now';
      }
      return 'Stockout predicted in ~$hours hours';
    }
    if (days < 3) {
      final rounded = days.toStringAsFixed(1);
      return 'Stockout predicted in ~$rounded days';
    }
    final rounded = days.round();
    return 'Stockout predicted in ~$rounded days';
  }

  String _formatHoursAgo(int hours) {
    if (hours < 1) return 'just now';
    if (hours == 1) return '1 hour ago';
    if (hours < 24) return '$hours hours ago';
    final days = hours ~/ 24;
    return days == 1 ? '1 day ago' : '$days days ago';
  }
}
