import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../billing/presentation/pages/home_page.dart';
import 'manage_page.dart';
import 'reports_page.dart';

/// Root navigation shell for owners and managers. Shows a 3-tab bottom nav
/// (Sell / Manage / Reports). Cashiers never see this — they get [HomePage]
/// directly from the router.
class OwnerShellPage extends StatefulWidget {
  const OwnerShellPage({super.key});

  @override
  State<OwnerShellPage> createState() => _OwnerShellPageState();
}

class _OwnerShellPageState extends State<OwnerShellPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    HomePage(),
    ManagePage(),
    ReportsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.point_of_sale),
            label: 'Sell',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.manage_accounts),
            label: 'Manage',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart),
            label: 'Reports',
          ),
        ],
        selectedItemColor: AppTheme.primary,
        unselectedItemColor: AppTheme.mutedForeground,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 8,
      ),
    );
  }
}
