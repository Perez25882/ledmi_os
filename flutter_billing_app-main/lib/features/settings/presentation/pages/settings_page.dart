import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:app_settings/app_settings.dart';

import '../../../../main.dart';
import '../../../../core/supabase/session_manager.dart';
import '../../../../core/theme/app_theme.dart';
import '../bloc/printer_bloc.dart';
import '../bloc/printer_event.dart';
import '../bloc/printer_state.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void initState() {
    super.initState();
    context.read<PrinterBloc>().add(InitPrinterEvent());
  }

  @override
  Widget build(BuildContext context) {
    final role = SessionManager.currentRole;
    final branchName = SessionManager.branchId ?? 'No branch';
    final userName = _roleLabel(role.name);
    final initial = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              size: 28, color: AppTheme.primary),
          onPressed: () => context.pop(),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppTheme.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Profile card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(userName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.foreground,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          '${role.name[0].toUpperCase()}${role.name.substring(1)} - $branchName',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.mutedForeground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppTheme.success,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Shift: Open',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.success,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // STORE section
            _buildSectionHeader('STORE'),
            _buildListGroup(
              children: [
                _buildListItem(
                  icon: Icons.storefront,
                  title: 'Shop Details',
                  onTap: () => context.push('/shop'),
                ),
                _buildDivider(),
                _buildListItem(
                  icon: Icons.inventory_2_outlined,
                  title: 'Products',
                  value: '45 items',
                  onTap: () => context.push('/products'),
                ),
                _buildDivider(),
                BlocConsumer<PrinterBloc, PrinterState>(
                  listener: (context, state) {
                    if (state.errorMessage != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(state.errorMessage!),
                          backgroundColor: AppTheme.destructive));
                    } else if (state.status == PrinterStatus.connected) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Connected to printer'),
                          backgroundColor: AppTheme.success));
                    }
                  },
                  builder: (context, state) {
                    return _buildListItem(
                      icon: Icons.print_outlined,
                      title: 'Print Receipt',
                      value: state.connectedMac != null
                          ? (state.connectedName ?? 'Connected')
                          : 'Bluetooth',
                      trailingWidget: state.status == PrinterStatus.scanning ||
                              state.status == PrinterStatus.connecting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.refresh,
                                      size: 20, color: AppTheme.primary),
                                  onPressed: () => context
                                      .read<PrinterBloc>()
                                      .add(RefreshPrinterEvent()),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.settings,
                                      size: 20, color: AppTheme.mutedForeground),
                                  onPressed: () => AppSettings.openAppSettings(
                                      type: AppSettingsType.bluetooth),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 24),

            // PAYMENTS section
            _buildSectionHeader('PAYMENTS'),
            _buildListGroup(
              children: [
                _buildListItem(
                  icon: Icons.point_of_sale,
                  title: 'Cash Drawer',
                  value: 'Active',
                ),
                _buildDivider(),
                _buildListItem(
                  icon: Icons.phone_android,
                  title: 'Mobile Money',
                  value: 'Connected',
                ),
                _buildDivider(),
                _buildListItem(
                  icon: Icons.credit_card,
                  title: 'Card Payments',
                  value: 'Paystack',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ACCOUNT section
            _buildSectionHeader('ACCOUNT'),
            _buildListGroup(
              children: [
                _buildListItem(
                  icon: Icons.person_outline,
                  title: 'Profile',
                ),
                _buildDivider(),
                _buildListItem(
                  icon: Icons.dark_mode_outlined,
                  title: 'Appearance',
                  value: 'Dark mode',
                  trailingWidget: ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeModeNotifier,
                    builder: (context, mode, _) {
                      return Switch(
                        value: mode == ThemeMode.dark,
                        activeThumbColor: AppTheme.primary,
                        onChanged: (enabled) =>
                            themeModeNotifier.setDarkMode(enabled),
                      );
                    },
                  ),
                  onTap: null,
                ),
                _buildDivider(),
                _buildListItem(
                  icon: Icons.logout,
                  title: 'Sign Out',
                  iconTint: AppTheme.destructive,
                  iconBg: AppTheme.destructive.withValues(alpha: 0.1),
                  titleColor: AppTheme.destructive,
                  onTap: () => _signOut(context),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _signOut(BuildContext context) async {
    await SessionManager.clearSensitiveData();
    if (context.mounted) context.go('/login');
  }

  String _roleLabel(String role) {
    switch (role.toLowerCase()) {
      case 'owner':
        return 'Owner';
      case 'manager':
        return 'Manager';
      case 'accountant':
        return 'Accountant';
      default:
        return 'Cashier';
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppTheme.mutedForeground,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildListGroup({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider() {
    return const Divider(height: 1, thickness: 1, color: AppTheme.border, indent: 64);
  }

  Widget _buildListItem({
    required IconData icon,
    required String title,
    String? value,
    Widget? trailingWidget,
    IconData? trailingIcon = Icons.chevron_right,
    Color iconTint = AppTheme.primary,
    Color iconBg = AppTheme.accent,
    Color titleColor = AppTheme.foreground,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconTint, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(title,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: titleColor,
                  )),
            ),
            if (value != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(value,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.mutedForeground,
                    )),
              ),
            if (trailingWidget != null)
              trailingWidget
            else if (trailingIcon != null)
              Icon(trailingIcon, color: AppTheme.mutedForeground, size: 20),
          ],
        ),
      ),
    );
  }
}
