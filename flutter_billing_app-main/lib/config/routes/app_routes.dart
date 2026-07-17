import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/supabase/auth_service.dart';
import '../../core/supabase/session_manager.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/branch_selection_page.dart';
import '../../features/billing/presentation/pages/home_page.dart';
import '../../features/product/presentation/pages/product_list_page.dart';
import '../../features/product/presentation/pages/add_product_page.dart';
import '../../features/product/presentation/pages/edit_product_page.dart';
import '../../features/shop/presentation/pages/shop_details_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/billing/presentation/pages/scanner_page.dart';
import '../../features/billing/presentation/pages/card_scanner_page.dart';
import '../../features/billing/presentation/pages/checkout_page.dart';
import '../../features/billing/presentation/pages/refund_page.dart';
import '../../features/product/domain/entities/product.dart';

final _authService = AuthService();

String? _authRedirect(BuildContext context, GoRouterState state) {
  final isAuthenticated = _authService.isAuthenticated;
  final hasBranch = SessionManager.businessId != null && SessionManager.branchId != null;
  final location = state.uri.path;

  if (!isAuthenticated && location != '/login') {
    return '/login';
  }

  if (isAuthenticated && !hasBranch && location != '/branch-selection') {
    return '/branch-selection';
  }

  if (isAuthenticated && hasBranch && (location == '/login' || location == '/branch-selection')) {
    return '/';
  }

  return null;
}

final router = GoRouter(
  initialLocation: '/',
  redirect: _authRedirect,
  refreshListenable: _AuthRefreshStream(),
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomePage(),
      routes: [
        GoRoute(
          path: 'scanner',
          builder: (context, state) => const ScannerPage(),
        ),
        GoRoute(
          path: 'checkout',
          builder: (context, state) => const CheckoutPage(),
        ),
        GoRoute(
          path: 'card-scanner',
          builder: (context, state) => const CardScannerPage(),
        ),
        GoRoute(
          path: 'refund',
          builder: (context, state) => const RefundPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/products',
      builder: (context, state) => const ProductListPage(),
      routes: [
        GoRoute(
          path: 'add',
          builder: (context, state) => const AddProductPage(),
        ),
        GoRoute(
          path: 'edit/:id',
          builder: (context, state) {
            final product = state.extra as Product?;
            if (product == null) {
              // If we land here without extra (e.g. deep link), go back to products for now.
              return const ProductListPage();
            }
            return EditProductPage(product: product);
          },
        ),
      ],
    ),
    GoRoute(
      path: '/shop',
      builder: (context, state) => const ShopDetailsPage(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/branch-selection',
      builder: (context, state) => const BranchSelectionPage(),
    ),
  ],
);

class _AuthRefreshStream extends ChangeNotifier {
  _AuthRefreshStream() {
    _authService.onAuthStateChange.listen((_) => notifyListeners());
  }
}
