import 'package:hive/hive.dart';

class SessionManager {
  static const String _boxName = 'session_box';
  static const String _businessIdKey = 'business_id';
  static const String _branchIdKey = 'branch_id';
  static const String _roleIdKey = 'role_id';
  static const String _shiftOpenKey = 'shift_open';
  static const String _shiftIdKey = 'shift_id';
  static const String _shiftOpenedAtKey = 'shift_opened_at';
  static const String _shiftFloatKey = 'shift_float';

  static late Box<String> _box;

  static Future<void> init() async {
    _box = await Hive.openBox<String>(_boxName);
  }

  static Future<void> setSession({
    required String businessId,
    required String branchId,
    String? roleId,
  }) async {
    await _box.put(_businessIdKey, businessId);
    await _box.put(_branchIdKey, branchId);
    if (roleId != null) {
      await _box.put(_roleIdKey, roleId);
    }
  }

  static String? get businessId => _box.get(_businessIdKey);
  static String? get branchId => _box.get(_branchIdKey);
  static String? get roleId => _box.get(_roleIdKey);

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

  static Future<void> clear() async {
    await _box.clear();
  }
}
