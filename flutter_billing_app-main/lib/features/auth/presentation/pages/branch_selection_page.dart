import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../product/presentation/bloc/product_bloc.dart';
import '../../../sync/data/services/supabase_sync_service.dart';

class BranchSelectionPage extends StatefulWidget {
  const BranchSelectionPage({super.key});

  @override
  State<BranchSelectionPage> createState() => _BranchSelectionPageState();
}

class _BranchSelectionPageState extends State<BranchSelectionPage> {
  bool _isLoading = true;
  String? _error;
  List<Map<String, dynamic>> _branches = [];

  final _client = SupabaseClientManager.client;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // 1. Get businesses + roles this user belongs to, joining custom_roles
      //    to resolve the role name and permission map (003_auth_helpers.sql).
      final rolesResponse = await _client
          .from('user_business_roles')
          .select('role_id, business_id, custom_roles(name, permissions)')
          .eq('user_id', userId);

      final rolesRows =
          (rolesResponse as List<dynamic>).cast<Map<String, dynamic>>();
      if (rolesRows.isEmpty) {
        setState(() {
          _branches = [];
          _isLoading = false;
        });
        return;
      }

      final businessIds = rolesRows
          .map((r) => r['business_id'] as String)
          .toSet()
          .toList();

      // 2. Load active branches for those businesses.
      final branchesResponse = await _client
          .from('branches')
          .select('id, name, is_active, business_id')
          .inFilter('business_id', businessIds)
          .eq('is_active', true)
          .order('name');

      final branchRows =
          (branchesResponse as List<dynamic>).cast<Map<String, dynamic>>();

      // 3. Map each branch to its user's role name + permissions in that business.
      final roleByBusiness = <String, Map<String, dynamic>>{};
      for (final row in rolesRows) {
        final cr = row['custom_roles'] as Map<String, dynamic>?;
        roleByBusiness[row['business_id'] as String] = {
          'role_id': row['role_id'] as String,
          'role_name': cr?['name'] as String? ?? '',
          'permissions': cr?['permissions'] as Map<String, dynamic>? ?? {},
        };
      }

      final mapped = branchRows.map((branch) {
        final bizId = branch['business_id'] as String;
        final role = roleByBusiness[bizId] ?? {};
        final perms = (role['permissions'] as Map<String, dynamic>)
            .entries
            .where((e) => e.value == true)
            .map((e) => e.key)
            .toSet();
        return {
          'id': branch['id'] as String,
          'name': branch['name'] as String,
          'business_id': bizId,
          'role_id': role['role_id'] as String? ?? '',
          'role_name': role['role_name'] as String? ?? '',
          'permissions': perms,
        };
      }).toList();

      setState(() {
        _branches = mapped;
        _isLoading = false;
      });
    } on PostgrestException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _selectBranch(Map<String, dynamic> branch) async {
    setState(() => _isLoading = true);

    try {
      await SessionManager.setSession(
        businessId: branch['business_id'] as String,
        branchId: branch['id'] as String,
        roleId: branch['role_id'] as String,
        roleName: branch['role_name'] as String,
        permissions: branch['permissions'] as Set<String>,
      );

      // Query onboarding status so the router can redirect synchronously.
      final bizId = branch['business_id'] as String;
      try {
        final rows = await _client
            .from('businesses')
            .select('onboarding_completed')
            .eq('id', bizId)
            .limit(1);
        final completed = rows.isNotEmpty
            ? (rows.first['onboarding_completed'] as bool? ?? false)
            : true;
        await SessionManager.setOnboardingCompleted(completed);
      } catch (_) {
        // Best-effort — assume completed so the user is not stuck.
        await SessionManager.setOnboardingCompleted(true);
      }

      await SupabaseSyncService().syncCatalog();

      if (mounted) {
        context.read<ProductBloc>().add(LoadProducts());
        if (SessionManager.onboardingCompleted) {
          context.go('/');
        } else {
          context.go('/onboarding/business-type');
        }
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await _client.auth.signOut();
    await SessionManager.clear();
  }

  @override
  Widget build(BuildContext context) {
    final user = _client.auth.currentUser;
    final userName = user?.email?.split('@').first ?? 'User';
    final initial = userName.isNotEmpty ? userName[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.destructive),
                    ),
                  ),
                )
              : _branches.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.store_outlined, size: 48, color: AppTheme.mutedForeground),
                          const SizedBox(height: 12),
                          const Text('No branches available.',
                              style: TextStyle(color: AppTheme.mutedForeground)),
                          const SizedBox(height: 16),
                          TextButton(onPressed: _signOut, child: const Text('Sign Out')),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        // Teal header
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(top: 60, left: 24, right: 24, bottom: 24),
                          decoration: const BoxDecoration(color: AppTheme.primary),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select Branch',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryForeground,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Choose your location to start',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.primaryForeground,
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.logout, color: AppTheme.primaryForeground),
                                    onPressed: _signOut,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        // User greeting card
                        Padding(
                          padding: const EdgeInsets.only(top: 24, left: 24, right: 24),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.card,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppTheme.border),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.06),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppTheme.accent,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Center(
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        userName,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.foreground,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        user?.email ?? '',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.mutedForeground,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Section label
                        const Padding(
                          padding: EdgeInsets.only(top: 24, left: 24, bottom: 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'AVAILABLE BRANCHES',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.mutedForeground,
                              ),
                            ),
                          ),
                        ),
                        // Branch list
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            itemCount: _branches.length,
                            itemBuilder: (context, index) {
                              final branch = _branches[index];
                              final role = (branch['role_name'] as String).toUpperCase();
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Material(
                                  color: AppTheme.card,
                                  borderRadius: BorderRadius.circular(16),
                                  child: InkWell(
                                    onTap: () => _selectBranch(branch),
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: AppTheme.border),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.06),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          // Branch icon
                                          Container(
                                            width: 48,
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: AppTheme.accent,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Center(
                                              child: Icon(Icons.store_outlined, color: AppTheme.primary, size: 24),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          // Branch info
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  branch['name'] as String,
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.foreground,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  role.isEmpty ? 'No role assigned' : role,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.mutedForeground,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.success,
                                                    borderRadius: BorderRadius.circular(11),
                                                  ),
                                                  child: const Text(
                                                    'Open',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: AppTheme.primaryForeground,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(Icons.chevron_right, color: AppTheme.mutedForeground),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
    );
  }
}
