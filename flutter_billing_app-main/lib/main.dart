import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'config/routes/app_routes.dart';
import 'core/data/hive_database.dart';
import 'core/service_locator.dart' as di;
import 'core/supabase/session_manager.dart';
import 'core/supabase/supabase_client.dart';
import 'core/theme/app_theme.dart';
import 'features/billing/presentation/bloc/billing_bloc.dart';
import 'features/product/presentation/bloc/product_bloc.dart';
import 'features/shop/presentation/bloc/shop_bloc.dart';
import 'features/settings/presentation/bloc/printer_bloc.dart';
import 'features/settings/presentation/bloc/printer_event.dart';
import 'features/owner/presentation/bloc/owner_bloc.dart';
import 'features/sync/data/services/offline_queue_service.dart';
import 'features/sync/data/services/offline_sync_service.dart';

/// Notifier that exposes the app [ThemeMode] and persists the user's
/// preference to the Hive settings box so it survives restarts.
class ThemeModeNotifier extends ValueNotifier<ThemeMode> {
  static const _key = 'dark_mode_enabled';

  ThemeModeNotifier() : super(_readFromDisk());

  static ThemeMode _readFromDisk() {
    final saved = HiveDatabase.settingsBox.get(_key);
    return saved == true ? ThemeMode.dark : ThemeMode.light;
  }

  bool get isDarkMode => value == ThemeMode.dark;

  void setDarkMode(bool enabled) {
    final mode = enabled ? ThemeMode.dark : ThemeMode.light;
    HiveDatabase.settingsBox.put(_key, enabled);
    value = mode;
  }
}

/// Global instance shared between [MyApp] and the Settings page.
final ThemeModeNotifier themeModeNotifier = ThemeModeNotifier();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HiveDatabase.init();
  await SessionManager.init();
  await SupabaseClientManager.initialize();
  await di.init();
  await di.sl<OfflineQueueService>().init();
  di.sl<OfflineSyncService>().startListening();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<ProductBloc>(
            create: (context) => di.sl<ProductBloc>()..add(LoadProducts())),
        BlocProvider<ShopBloc>(
            create: (context) => di.sl<ShopBloc>()..add(LoadShopEvent())),
        BlocProvider<BillingBloc>(
            create: (context) => BillingBloc(
                  getProductByBarcodeUseCase: di.sl(),
                  checkoutService: di.sl(),
                )),
        BlocProvider<PrinterBloc>(
            create: (context) => di.sl<PrinterBloc>()..add(InitPrinterEvent())),
        BlocProvider<OwnerBloc>(
            create: (context) => di.sl<OwnerBloc>()),
      ],
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeModeNotifier,
        builder: (context, mode, _) {
          return MaterialApp.router(
            title: 'Billing App',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: mode,
            routerConfig: router,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
