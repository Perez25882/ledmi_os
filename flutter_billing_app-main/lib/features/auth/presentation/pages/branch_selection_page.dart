import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/supabase/session_manager.dart';
import '../../../../core/supabase/supabase_client.dart';
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

      await SupabaseSyncService().syncCatalog();

      if (mounted) {
        context.read<ProductBloc>().add(LoadProducts());
        context.go('/');
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Branch'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : _branches.isEmpty
                  ? const Center(child: Text('No branches available.'))
                  : ListView.builder(
                      itemCount: _branches.length,
                      itemBuilder: (context, index) {
                        final branch = _branches[index];
                        final role = (branch['role_name'] as String)
                            .toUpperCase();
                        return ListTile(
                          title: Text(branch['name'] as String),
                          subtitle: Text(
                            role.isEmpty ? 'No role assigned' : role,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _selectBranch(branch),
                        );
                      },
                    ),
    );
  }
}
