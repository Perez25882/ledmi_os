import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/owner_bloc.dart';

/// Quick-glance reports for the owner standing in the shop. Shows last 7 days
/// revenue as simple custom bars, top 5 products, and payment method breakdown.
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadWeeklyReport());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        automaticallyImplyLeading: false,
      ),
      body: BlocBuilder<OwnerBloc, OwnerState>(
        builder: (context, state) {
          if (state.isLoading && state.weeklyReport == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null && state.weeklyReport == null) {
            return _buildErrorView(context, state.error!);
          }
          final report = state.weeklyReport;
          if (report == null) {
            return const Center(child: Text('No data available'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              context.read<OwnerBloc>().add(LoadWeeklyReport());
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildRevenueChart(context, report.dailyRevenue),
                const SizedBox(height: 16),
                _buildTopProducts(context, report.topProducts),
                const SizedBox(height: 16),
                _buildPaymentBreakdown(context, report.paymentBreakdown),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildRevenueChart(BuildContext context, List<DailyRevenue> data) {
    final maxRevenue = data.isEmpty
        ? 1.0
        : data.map((d) => d.revenue).reduce((a, b) => a > b ? a : b);
    final safeMax = maxRevenue <= 0 ? 1.0 : maxRevenue;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Last 7 Days Revenue',
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
              ],
            ),
            const SizedBox(height: 20),
            if (data.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No sales in the last 7 days',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mutedForeground,
                          )),
                ),
              )
            else
              SizedBox(
                height: 160,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: data.map((d) {
                    final barHeight = (d.revenue / safeMax) * 120;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              d.revenue > 0
                                  ? d.revenue.toStringAsFixed(0)
                                  : '',
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.mutedForeground,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: barHeight.clamp(2.0, 120.0),
                              decoration: const BoxDecoration(
                                color: AppTheme.primary,
                                borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(6)),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _dayLabel(d.date),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.mutedForeground,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProducts(BuildContext context, List<TopProduct> products) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star, color: AppTheme.warning, size: 20),
                const SizedBox(width: 8),
                Text('Top 5 Products This Week',
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
              ],
            ),
            const SizedBox(height: 12),
            if (products.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('No product sales this week',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mutedForeground,
                          )),
                ),
              )
            else
              ...products.asMap().entries.map((entry) {
                final index = entry.key;
                final product = entry.value;
                return _buildTopProductTile(context, index + 1, product);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProductTile(
      BuildContext context, int rank, TopProduct product) {
    final colors = [
      AppTheme.warning,
      AppTheme.mutedForeground,
      AppTheme.mutedForeground,
      AppTheme.mutedForeground,
      AppTheme.mutedForeground,
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colors[rank - 1].withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$rank',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colors[rank - 1],
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text('${product.unitsSold} units sold',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.mutedForeground,
                        )),
              ],
            ),
          ),
          Text(
            'GHS ${product.revenue.toStringAsFixed(2)}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentBreakdown(
      BuildContext context, Map<String, double> breakdown) {
    final total =
        breakdown.values.fold(0.0, (sum, v) => sum + v);
    final entries = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payments, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Payment Methods This Week',
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('No payments this week',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.mutedForeground,
                          )),
                ),
              )
            else
              ...entries.map((e) => _buildPaymentRow(
                    context,
                    _methodLabel(e.key),
                    e.value,
                    total,
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(
      BuildContext context, String method, double amount, double total) {
    final percentage = total > 0 ? (amount / total * 100) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(method,
                    style:
                        Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            )),
              ),
              Text(
                'GHS ${amount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: AppTheme.mutedForeground,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total > 0 ? (amount / total).clamp(0.0, 1.0) : 0,
              minHeight: 6,
              backgroundColor: AppTheme.muted,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  String _methodLabel(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'Cash';
      case 'momo':
      case 'mobile_money':
        return 'MoMo';
      case 'card':
        return 'Card';
      default:
        return method[0].toUpperCase() + method.substring(1);
    }
  }

  String _dayLabel(DateTime date) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[date.weekday - 1];
  }

  Widget _buildErrorView(BuildContext context, String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppTheme.destructive, size: 48),
          const SizedBox(height: 16),
          Text(error, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () =>
                context.read<OwnerBloc>().add(LoadWeeklyReport()),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
