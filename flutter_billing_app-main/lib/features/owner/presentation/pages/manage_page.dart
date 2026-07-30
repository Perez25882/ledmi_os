import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../bloc/owner_bloc.dart';

/// Owner/manager dashboard. Shows today's summary at a glance and quick
/// action cards for stock-in, low-stock alerts, and quick product add.
class ManagePage extends StatefulWidget {
  const ManagePage({super.key});

  @override
  State<ManagePage> createState() => _ManagePageState();
}

class _ManagePageState extends State<ManagePage> {
  @override
  void initState() {
    super.initState();
    context.read<OwnerBloc>().add(LoadTodaySummary());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage'),
        automaticallyImplyLeading: false,
      ),
      body: BlocBuilder<OwnerBloc, OwnerState>(
        builder: (context, state) {
          if (state.isLoading && state.todaySummary == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.error != null && state.todaySummary == null) {
            return _buildErrorView(context, state.error!);
          }
          return RefreshIndicator(
            onRefresh: () async {
              context.read<OwnerBloc>().add(LoadTodaySummary());
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTodaySummaryCard(context, state),
                const SizedBox(height: 16),
                Text('Quick Actions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
                const SizedBox(height: 12),
                _buildQuickActionGrid(context),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTodaySummaryCard(BuildContext context, OwnerState state) {
    final summary = state.todaySummary;
    final revenue = summary?.revenue ?? 0;
    final count = summary?.transactionCount ?? 0;
    final avgBasket = summary?.avgBasketValue ?? 0;
    final breakdown = summary?.paymentBreakdown ?? {};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.today, color: AppTheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Today\'s Summary',
                    style:
                        Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            )),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                    child: _buildStatTile(
                  context,
                  'Revenue',
                  'GHS ${revenue.toStringAsFixed(2)}',
                  AppTheme.primary,
                )),
                Expanded(
                    child: _buildStatTile(
                  context,
                  'Transactions',
                  '$count',
                  AppTheme.foreground,
                )),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                    child: _buildStatTile(
                  context,
                  'Avg Basket',
                  'GHS ${avgBasket.toStringAsFixed(2)}',
                  AppTheme.foreground,
                )),
                Expanded(child: _buildPaymentBreakdown(context, breakdown)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(
      BuildContext context, String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.mutedForeground,
                )),
        const SizedBox(height: 4),
        Text(value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                )),
      ],
    );
  }

  Widget _buildPaymentBreakdown(
      BuildContext context, Map<String, double> breakdown) {
    if (breakdown.isEmpty) {
      return _buildStatTile(context, 'Payments', '—', AppTheme.mutedForeground);
    }
    final entries = breakdown.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final text = entries
        .map((e) => '${_methodLabel(e.key)}: ${e.value.toStringAsFixed(0)}')
        .join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payments',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.mutedForeground,
                )),
        const SizedBox(height: 4),
        Text(text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                )),
      ],
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
        return method;
    }
  }

  Widget _buildQuickActionGrid(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.1,
      children: [
        _buildActionCard(
          context,
          icon: Icons.inventory_2_outlined,
          title: 'Receive Delivery',
          subtitle: 'Record stock-in',
          color: AppTheme.primary,
          onTap: () => context.push('/manage/stock-in'),
        ),
        _buildActionCard(
          context,
          icon: Icons.warning_amber_rounded,
          title: 'Low Stock',
          subtitle: 'Reorder alerts',
          color: AppTheme.warning,
          onTap: () => context.push('/manage/low-stock'),
        ),
        _buildActionCard(
          context,
          icon: Icons.add_circle_outline,
          title: 'Quick Add Product',
          subtitle: 'Add to catalog',
          color: AppTheme.success,
          onTap: () => context.push('/manage/quick-add'),
        ),
        _buildActionCard(
          context,
          icon: Icons.receipt_long_outlined,
          title: 'Products',
          subtitle: 'Manage catalog',
          color: AppTheme.foreground,
          onTap: () => context.push('/products'),
        ),
      ],
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      )),
              Text(subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.mutedForeground,
                      )),
            ],
          ),
        ),
      ),
    );
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
                context.read<OwnerBloc>().add(LoadTodaySummary()),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
