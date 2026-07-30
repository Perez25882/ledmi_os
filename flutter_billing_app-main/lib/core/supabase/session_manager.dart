import 'package:hive/hive.dart';

enum AppRole { owner, manager, cashier, accountant, unknown }

AppRole _parseRole(String? name) {
  switch (name) {
    case 'owner':
      return AppRole.owner;
    case 'manager':
      return AppRole.manager;
    case 'cashier':
      return AppRole.cashier;
    case 'accountant':
      return AppRole.accountant;
    default:
      return AppRole.unknown;
  }
}

class SessionManager {
  static const String _boxName = 'session_box';
  static const String _businessIdKey = 'business_id';
  static const String _branchIdKey = 'branch_id';
  static const String _roleIdKey = 'role_id';
  static const String _roleNameKey = 'role_name';
  static const String _permissionsKey = 'permissions';
  static const String _shiftOpenKey = 'shift_open';
  static const String _shiftIdKey = 'shift_id';
  static const String _shiftOpenedAtKey = 'shift_opened_at';
  static const String _shiftFloatKey = 'shift_float';
  static const String _reLoginRequiredKey = 're_login_required';
  static const String _onboardingCompletedKey = 'onboarding_completed';

  static late Box<String> _box;

  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  static Future<void> setSession({
    required String businessId,
    required String branchId,
    String? roleId,
    String? roleName,
    Set<String>? permissions,
  }) async {
    await _box.put(_businessIdKey, businessId);
    await _box.put(_branchIdKey, branchId);
    if (roleId != null) {
      await _box.put(_roleIdKey, roleId);
    }
    if (roleName != null) {
      await _box.put(_roleNameKey, roleName);
    }
    if (permissions != null) {
      await _box.put(_permissionsKey, permissions.join(','));
    }
  }

  static String? get businessId => _box.get(_businessIdKey);
  static String? get branchId => _box.get(_branchIdKey);
  static String? get roleId => _box.get(_roleIdKey);
  static String? get roleName => _box.get(_roleNameKey);

  static AppRole get currentRole => _parseRole(roleName);

  static Set<String> get permissions {
    final raw = _box.get(_permissionsKey);
    if (raw == null || raw.isEmpty) return {};
    return raw.split(',').where((p) => p.isNotEmpty).toSet();
  }

  /// Mirrors the backend `user_has_permission(business_id, permission)` check
  /// (003_auth_helpers.sql). Permission names match the JSONB keys seeded in
  /// 001_default_roles.sql: manage_products, manage_inventory, manage_users,
  /// process_sales, view_reports, view_inventory, view_sales.
  static bool hasPermission(String permission) =>
      permissions.contains(permission);

  static bool get isOwner => currentRole == AppRole.owner;
  static bool get isManager => currentRole == AppRole.manager;
  static bool get isCashier => currentRole == AppRole.cashier;
  static bool get isAccountant => currentRole == AppRole.accountant;

  /// Owner or manager — used to gate admin/settings routes. Mirrors the
  /// dashboard `canAccessPage` helper for users/settings pages.
  static bool get canManageBusiness =>
      isOwner || isManager;

  /// Whether onboarding has been completed for the current business. Cached
  /// in Hive so the router can redirect synchronously. Set during branch
  /// selection (queried from `businesses.onboarding_completed`) and updated
  /// when the onboarding flow finishes.
  static bool get onboardingCompleted =>
      _box.get(_onboardingCompletedKey) == 'true';

  static Future<void> setOnboardingCompleted(bool value) async {
    await _box.put(_onboardingCompletedKey, value ? 'true' : 'false');
  }

  /// SYNC_PROTOCOL §3.2: when the token refresh fails, sync must stop and the
  /// cashier must re-authenticate. This flag is checked by the sync drain and
  /// can be observed by the router to redirect to login. The offline queue is
  /// NOT cleared.
  static bool get reLoginRequired =>
      _box.get(_reLoginRequiredKey) == 'true';

  static Future<void> markReLoginRequired() async {
    await _box.put(_reLoginRequiredKey, 'true');
  }

  static Future<void> clearReLoginRequired() async {
    await _box.delete(_reLoginRequiredKey);
  }

  static bool get isShiftOpen => _box.get(_shiftOpenKey) == 'true';
  static String? get shiftId => _box.get(_shiftIdKey);
  static DateTime? get shiftOpenedAt {
    final value = _box.get(_shiftOpenedAtKey);
    return value != null ? DateTime.tryParse(value) : null;
  }

  static double? get shiftFloat {
    final value = _box.get(_shiftFloatKey);
    return value != null ? double.tryParse(value) : null;
  }

  static Future<void> openShift({required String shiftId, required double float}) async {
    await _box.put(_shiftOpenKey, 'true');
    await _box.put(_shiftIdKey, shiftId);
    await _box.put(_shiftOpenedAtKey, DateTime.now().toIso8601String());
    await _box.put(_shiftFloatKey, float.toString());
  }

  static Future<void> closeShift() async {
    await _box.put(_shiftOpenKey, 'false');
    await _box.delete(_shiftIdKey);
    await _box.delete(_shiftOpenedAtKey);
    await _box.delete(_shiftFloatKey);
  }

  /// Clears local sensitive session context (business/branch/role/shift) per
  /// SYNC_PROTOCOL §3.2. The offline sale queue lives in a separate Hive box
  /// and is intentionally preserved so pending ops survive re-authentication.
  /// The re-login flag is also preserved so the router can redirect to login.
  static Future<void> clearSensitiveData() async {
    await _box.delete(_businessIdKey);
    await _box.delete(_branchIdKey);
    await _box.delete(_roleIdKey);
    await _box.delete(_roleNameKey);
    await _box.delete(_permissionsKey);
    await _box.delete(_onboardingCompletedKey);
    await _box.put(_shiftOpenKey, 'false');
    await _box.delete(_shiftIdKey);
    await _box.delete(_shiftOpenedAtKey);
    await _box.delete(_shiftFloatKey);
  }

  static Future<void> clear() async {
    await _box.clear();
  }
}
