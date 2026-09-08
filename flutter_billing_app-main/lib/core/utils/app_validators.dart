class AppValidators {
  // Deliberately permissive: catches the mistakes cashiers actually make on a
  // phone keyboard (missing "@", trailing dot, spaces) without rejecting valid
  // addresses. The server is the real authority.
  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@.]+$');

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) {
      return 'Please enter your email';
    }
    if (!_emailPattern.hasMatch(email)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? Function(String?) required(String message) {
    return (String? value) {
      if (value == null || value.trim().isEmpty) {
        return message;
      }
      return null;
    };
  }

  static String? price(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter a price';
    }
    if (double.tryParse(value) == null) {
      return 'Please enter a valid number';
    }
    if (double.parse(value) < 0) {
      return 'Price cannot be negative';
    }
    return null;
  }
}
