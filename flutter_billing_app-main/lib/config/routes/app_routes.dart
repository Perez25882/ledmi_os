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
import '../../features/billing/presentation/pages/receipt_preview_page.dart';
import '../../features/billing/presentation/pages/refund_page.dart';
import '../../features/owner/presentation/pages/owner_shell_page.dart';
import '../../features/owner/presentation/pages/stock_in_page.dart';
import '../../features/owner/presentation/pages/low_stock_page.dart';
import '../../features/owner/presentation/pages/quick_add_product_page.dart';
import '../../features/owner/presentation/pages/reports_page.dart';
import '../../features/onboarding/presentation/pages/business_type_page.dart';
import '../../features/onboarding/presentation/pages/starter_catalog_page.dart';
import '../../features/onboarding/presentation/pages/shelf_scan_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_wrapper.dart';
import '../../features/product/domain/entities/product.dart';

final _authService = AuthService();

/// Routes a cashier must never reach. Cashiers (Adjoa) are restricted to
/// checkout + their own shift — they cannot manage products, edit shop
/// details, or open settings beyond printer pairing (handled in-page).
const _cashierBlocked = <String>{
  '/products/add',
  '/shop',
  '/manage',
  '/manage/stock-in',
  '/manage/low-stock',
  '/manage/quick-add',
  '/manage/reports',
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

/// Whether [location] is any of the onboarding routes.
bool _isOnboardingRoute(String location) =>
    location == '/onboarding' ||
    location.startsWith('/onboarding/');

/// The home route for the current user — managers/owners land on `/manage`,
/// everyone else on `/`.
String _homeRoute() =>
    SessionManager.canManageBusiness ? '/manage' : '/';

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
    // After login + branch selection, send incomplete onboarding to step 1.
    if (!SessionManager.onboardingCompleted) {
      return '/onboarding/business-type';
    }
    return _homeRoute();
  }

  // Onboarding gate: if onboarding is not complete, force the user into the
  // onboarding flow (unless they are already there).
  if (isAuthenticated && hasBranch && !SessionManager.onboardingCompleted) {
    if (!_isOnboardingRoute(location)) {
      return '/onboarding/business-type';
    }
    return null; // allow onboarding routes through
  }

  // Onboarding is complete — block access to onboarding routes.
  if (isAuthenticated && hasBranch &&
      SessionManager.onboardingCompleted &&
      _isOnboardingRoute(location)) {
    return _homeRoute();
  }

  if (isAuthenticated && hasBranch) {
    if (_isCashierBlocked(location) ||
        _isManagementOnlyBlocked(location) ||
        _isManageProductsBlocked(location)) {
      return _homeRoute();
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
          path: 'receipt',
          builder: (context, state) {
            final data = state.extra as ReceiptData?;
            if (data == null) {
              return const HomePage();
            }
            return ReceiptPreviewPage(data: data);
          },
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
      path: '/manage',
      builder: (context, state) => const OwnerShellPage(),
      routes: [
        GoRoute(
          path: 'stock-in',
          builder: (context, state) => StockInPage(
            preselectedProduct:
                state.extra as Map<String, dynamic>?,
          ),
        ),
        GoRoute(
          path: 'low-stock',
          builder: (context, state) => const LowStockPage(),
        ),
        GoRoute(
          path: 'quick-add',
          builder: (context, state) => const QuickAddProductPage(),
        ),
        GoRoute(
          path: 'reports',
          builder: (context, state) => const ReportsPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginPage(),
    ),
    GoRoute(
      path: '/branch-selection',
      builder: (context, state) => const BranchSelectionPage(),
    ),
    // Onboarding flow — wrapped in a shared BlocProvider via OnboardingWrapper.
    GoRoute(
      path: '/onboarding',
      redirect: (context, state) => '/onboarding/business-type',
    ),
    ShellRoute(
      builder: (context, state, child) =>
          OnboardingWrapper(child: child),
      routes: [
        GoRoute(
          path: '/onboarding/business-type',
          builder: (context, state) => const BusinessTypePage(),
        ),
        GoRoute(
          path: '/onboarding/starter-catalog',
          builder: (context, state) => const StarterCatalogPage(),
        ),
        GoRoute(
          path: '/onboarding/shelf-scan',
          builder: (context, state) => const ShelfScanPage(),
        ),
      ],
    ),
  ],
);

class _AuthRefreshStream extends ChangeNotifier {
  _AuthRefreshStream() {
    _authService.onAuthStateChange.listen((_) => notifyListeners());
  }
}
