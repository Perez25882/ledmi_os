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

/// Routes a cashier must never reach. Cashiers (Adjoa) are restricted to
/// checkout + their own shift — they cannot manage products, edit shop
/// details, or open settings beyond printer pairing (handled in-page).
const _cashierBlocked = <String>{
  '/products/add',
  '/shop',
};

/// Routes restricted to owner/manager. Mirrors the dashboard `canAccessPage`
/// helper for catalog/users/settings pages (permissions.ts).
const _managementOnly = <String>{
  '/products/add',
};

/// Path prefixes that require manage_products permission. Cashiers can view
/// the product list (read-only) but cannot add or edit.
const _manageProductsPrefixes = <String>{
  '/products/add',
  '/products/edit/',
};

bool _isCashierBlocked(String location) {
  if (SessionManager.isCashier) {
    for (final blocked in _cashierBlocked) {
      if (location == blocked || location.startsWith('$blocked/')) {
        return true;
      }
    }
  }
  return false;
}

bool _isManagementOnlyBlocked(String location) {
  if (!SessionManager.canManageBusiness) {
    for (final restricted in _managementOnly) {
      if (location == restricted || location.startsWith('$restricted/')) {
        return true;
      }
    }
  }
  return false;
}

bool _isManageProductsBlocked(String location) {
  if (SessionManager.hasPermission('manage_products')) return false;
  for (final prefix in _manageProductsPrefixes) {
    if (location == prefix || location.startsWith(prefix)) {
      return true;
    }
  }
  return false;
}

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

  if (isAuthenticated && hasBranch) {
    if (_isCashierBlocked(location) ||
        _isManagementOnlyBlocked(location) ||
        _isManageProductsBlocked(location)) {
      return '/';
    }
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
