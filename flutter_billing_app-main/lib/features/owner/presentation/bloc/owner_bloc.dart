import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../data/services/stock_prediction_service.dart';
import '../../domain/entities/stock_prediction.dart';

part 'owner_event.dart';
part 'owner_state.dart';

class OwnerBloc extends Bloc<OwnerEvent, OwnerState> {
  final SupabaseClient _client;
  final Uuid _uuid;
  final StockPredictionService _predictionService;

  OwnerBloc({
    SupabaseClient? client,
    Uuid? uuid,
    StockPredictionService? predictionService,
  })  : _client = client ?? SupabaseClientManager.client,
        _uuid = uuid ?? const Uuid(),
        _predictionService = predictionService ?? StockPredictionService(),
        super(const OwnerState()) {
    on<LoadTodaySummary>(_onLoadTodaySummary);
    on<LoadLowStock>(_onLoadLowStock);
    on<LoadStockPredictions>(_onLoadStockPredictions);
    on<DismissStockAlert>(_onDismissStockAlert);
    on<LoadStockInLog>(_onLoadStockInLog);
    on<RecordStockIn>(_onRecordStockIn);
    on<QuickAddProduct>(_onQuickAddProduct);
    on<LoadWeeklyReport>(_onLoadWeeklyReport);
    on<MarkLowStockOrdered>(_onMarkLowStockOrdered);
  }

  Future<void> _onLoadTodaySummary(
      LoadTodaySummary event, Emitter<OwnerState> emit) async {
    final branchId = SessionManager.branchId;
    if (branchId == null) {
      emit(state.copyWith(error: 'No branch selected'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      // Join sales → invoices for total; sales → payments for method breakdown.
      final rows = await _client
          .from('sales')
          .select('''
            id,
            created_at,
            invoice:invoices(total),
            payment:payments(method)
          ''')
          .eq('branch_id', branchId)
          .gte('created_at', _startOfToday().toIso8601String())
          .lt('created_at', _endOfToday().toIso8601String());

      double revenue = 0;
      int count = rows.length;
      final Map<String, double> paymentBreakdown = {};

      for (final row in rows) {
        final invoice = row['invoice'] as Map<String, dynamic>?;
        if (invoice != null) {
          revenue += (invoice['total'] as num?)?.toDouble() ?? 0;
        }
        final payment = row['payment'] as Map<String, dynamic>?;
        if (payment != null) {
          final method = (payment['method'] as String?) ?? 'unknown';
          final total = (invoice?['total'] as num?)?.toDouble() ?? 0;
          paymentBreakdown[method] =
              (paymentBreakdown[method] ?? 0) + total;
        }
      }

      final avgBasket = count > 0 ? revenue / count : 0.0;

      emit(state.copyWith(
        isLoading: false,
        todaySummary: TodaySummary(
          revenue: revenue,
          transactionCount: count,
          avgBasketValue: avgBasket,
          paymentBreakdown: paymentBreakdown,
        ),
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadLowStock(
      LoadLowStock event, Emitter<OwnerState> emit) async {
    final branchId = SessionManager.branchId;
    if (branchId == null) {
      emit(state.copyWith(error: 'No branch selected'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      final rows = await _client
          .from('inventory')
          .select('''
            quantity,
            reorder_level,
            product:products(id, name, barcode)
          ''')
          .eq('branch_id', branchId)
          .filter('quantity', 'lte', 'reorder_level');

      final items = <LowStockItem>[];
      for (final row in rows) {
        final product = row['product'] as Map<String, dynamic>?;
        if (product == null) continue;
        final qty = (row['quantity'] as num?)?.toInt() ?? 0;
        final reorder = (row['reorder_level'] as num?)?.toInt() ?? 10;
        items.add(LowStockItem(
          productId: product['id'] as String,
          name: (product['name'] as String?) ?? 'Unknown',
          barcode: (product['barcode'] as String?) ?? '',
          currentStock: qty,
          reorderLevel: reorder,
          suggestedReorderQty: reorder * 2,
        ));
      }

      emit(state.copyWith(isLoading: false, lowStockItems: items));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadStockPredictions(
      LoadStockPredictions event, Emitter<OwnerState> emit) async {
    final branchId = SessionManager.branchId;
    if (branchId == null) {
      emit(state.copyWith(error: 'No branch selected'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      final predictions = await _predictionService.fetchPredictions();
      emit(state.copyWith(isLoading: false, stockPredictions: predictions));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onDismissStockAlert(
      DismissStockAlert event, Emitter<OwnerState> emit) async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    if (businessId == null || branchId == null) {
      emit(state.copyWith(error: 'No business/branch selected'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null, successMessage: null));
    try {
      await _client.from('activity_logs').insert({
        'business_id': businessId,
        'branch_id': branchId,
        'action': 'stock_alert_dismissed',
        'entity_table': 'products',
        'entity_id': event.productId,
        'metadata': {
          'product_name': event.productName,
        },
      });

      final remaining = state.stockPredictions
          .where((p) => p.productId != event.productId)
          .toList();

      emit(state.copyWith(
        isLoading: false,
        stockPredictions: remaining,
        successMessage: 'Dismissed alert for "${event.productName}"',
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadStockInLog(
      LoadStockInLog event, Emitter<OwnerState> emit) async {
    final branchId = SessionManager.branchId;
    if (branchId == null) return;

    try {
      final rows = await _client
          .from('inventory_logs')
          .select('''
            quantity:change_amount,
            reason,
            created_at,
            product:products(name)
          ''')
          .eq('branch_id', branchId)
          .eq('reason', 'delivery')
          .order('created_at', ascending: false)
          .limit(20);

      final log = <StockInLogEntry>[];
      for (final row in rows) {
        final product = row['product'] as Map<String, dynamic>?;
        log.add(StockInLogEntry(
          productName: (product?['name'] as String?) ?? 'Unknown',
          quantity: (row['quantity'] as num?)?.toInt() ?? 0,
          reason: (row['reason'] as String?) ?? 'delivery',
          createdAt: DateTime.parse(row['created_at'] as String),
        ));
      }

      emit(state.copyWith(stockInLog: log));
    } catch (_) {
      // Best-effort log load; don't surface errors.
    }
  }

  Future<void> _onRecordStockIn(
      RecordStockIn event, Emitter<OwnerState> emit) async {
    final branchId = SessionManager.branchId;
    if (branchId == null) {
      emit(state.copyWith(error: 'No branch selected'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null, successMessage: null));
    try {
      final idempotencyKey = _uuid.v4();

      await _client.rpc('process_stock_in', params: {
        'p_branch_id': branchId,
        'p_product_id': event.productId,
        'p_quantity': event.quantity,
        'p_reason': 'delivery',
        'p_idempotency_key': idempotencyKey,
      });

      // Optionally update cost_price if provided.
      if (event.costPrice != null) {
        await _client
            .from('products')
            .update({'cost_price': event.costPrice}).eq('id', event.productId);
      }

      emit(state.copyWith(
        isLoading: false,
        successMessage:
            'Recorded ${event.quantity} units delivered successfully',
      ));
      add(LoadStockInLog());
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onQuickAddProduct(
      QuickAddProduct event, Emitter<OwnerState> emit) async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    if (businessId == null || branchId == null) {
      emit(state.copyWith(error: 'No business/branch selected'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null, successMessage: null));
    try {
      // Insert product.
      final productRows = await _client.from('products').insert({
        'business_id': businessId,
        'name': event.name,
        'barcode': event.barcode,
        'selling_price': event.price,
        'cost_price': event.costPrice ?? 0,
        'category_id': null,
      }).select('id');

      final productId = productRows.first['id'] as String;

      // Create inventory row for this branch.
      await _client.from('inventory').insert({
        'product_id': productId,
        'business_id': businessId,
        'branch_id': branchId,
        'quantity': event.stockQty,
        'reorder_level': 5,
      });

      // Cache barcode if it was looked up.
      await _client.from('barcode_cache').upsert({
        'barcode': event.barcode,
        'name': event.name,
        'category': event.category,
        'source': 'manual_entry',
      }).select();

      emit(state.copyWith(
        isLoading: false,
        successMessage: 'Product "${event.name}" added successfully',
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadWeeklyReport(
      LoadWeeklyReport event, Emitter<OwnerState> emit) async {
    final branchId = SessionManager.branchId;
    if (branchId == null) {
      emit(state.copyWith(error: 'No branch selected'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null));
    try {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7));

      // Daily revenue for last 7 days.
      final salesRows = await _client
          .from('sales')
          .select('created_at, invoice:invoices(total)')
          .eq('branch_id', branchId)
          .gte('created_at', weekAgo.toIso8601String())
          .order('created_at', ascending: true);

      final Map<String, DailyRevenue> dailyMap = {};
      for (final row in salesRows) {
        final createdStr = row['created_at'] as String;
        final date = DateTime.parse(createdStr);
        final dayKey =
            '${date.year}-${date.month}-${date.day}';
        final invoice = row['invoice'] as Map<String, dynamic>?;
        final total = (invoice?['total'] as num?)?.toDouble() ?? 0;
        if (dailyMap.containsKey(dayKey)) {
          final existing = dailyMap[dayKey]!;
          dailyMap[dayKey] = DailyRevenue(
            date: existing.date,
            revenue: existing.revenue + total,
            transactionCount: existing.transactionCount + 1,
          );
        } else {
          dailyMap[dayKey] = DailyRevenue(
            date: date,
            revenue: total,
            transactionCount: 1,
          );
        }
      }
      final dailyRevenue = dailyMap.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date));

      // Top 5 products this week.
      final topRows = await _client
          .from('sale_items')
          .select('''
            quantity,
            subtotal,
            sale:sales!inner(branch_id, created_at),
            product:products(name)
          ''')
          .eq('sale.branch_id', branchId)
          .gte('sale.created_at', weekAgo.toIso8601String());

      final Map<String, TopProduct> productMap = {};
      for (final row in topRows) {
        final product = row['product'] as Map<String, dynamic>?;
        final name = (product?['name'] as String?) ?? 'Unknown';
        final qty = (row['quantity'] as num?)?.toInt() ?? 0;
        final revenue = (row['subtotal'] as num?)?.toDouble() ?? 0;
        if (productMap.containsKey(name)) {
          final existing = productMap[name]!;
          productMap[name] = TopProduct(
            name: name,
            unitsSold: existing.unitsSold + qty,
            revenue: existing.revenue + revenue,
          );
        } else {
          productMap[name] = TopProduct(
            name: name,
            unitsSold: qty,
            revenue: revenue,
          );
        }
      }
      final topProducts = productMap.values.toList()
        ..sort((a, b) => b.revenue.compareTo(a.revenue));
      final top5 = topProducts.take(5).toList();

      // Payment method breakdown this week.
      final paymentRows = await _client
          .from('sales')
          .select('invoice:invoices(total), payment:payments(method)')
          .eq('branch_id', branchId)
          .gte('created_at', weekAgo.toIso8601String());

      final Map<String, double> paymentBreakdown = {};
      for (final row in paymentRows) {
        final payment = row['payment'] as Map<String, dynamic>?;
        final invoice = row['invoice'] as Map<String, dynamic>?;
        final method = (payment?['method'] as String?) ?? 'unknown';
        final total = (invoice?['total'] as num?)?.toDouble() ?? 0;
        paymentBreakdown[method] =
            (paymentBreakdown[method] ?? 0) + total;
      }

      emit(state.copyWith(
        isLoading: false,
        weeklyReport: WeeklyReport(
          dailyRevenue: dailyRevenue,
          topProducts: top5,
          paymentBreakdown: paymentBreakdown,
        ),
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onMarkLowStockOrdered(
      MarkLowStockOrdered event, Emitter<OwnerState> emit) async {
    final businessId = SessionManager.businessId;
    final branchId = SessionManager.branchId;
    if (businessId == null || branchId == null) {
      emit(state.copyWith(error: 'No business/branch selected'));
      return;
    }

    emit(state.copyWith(isLoading: true, error: null, successMessage: null));
    try {
      await _client.from('activity_logs').insert({
        'business_id': businessId,
        'branch_id': branchId,
        'action': 'reorder_placed',
        'entity_table': 'products',
        'entity_id': event.productId,
        'metadata': {
          'product_name': event.productName,
          'reorder_qty': event.reorderQty,
        },
      });

      emit(state.copyWith(
        isLoading: false,
        successMessage:
            'Marked "${event.productName}" as ordered (${event.reorderQty} units)',
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  DateTime _startOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _endOfToday() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .add(const Duration(days: 1));
  }
}
