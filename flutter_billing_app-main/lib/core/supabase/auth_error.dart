import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns auth failures into short, actionable copy for the sign-in screen.
///
/// Without this, a failed sign-in renders the raw SDK object — e.g.
/// `AuthApiException(message: Invalid login credentials, statusCode: 400,
/// code: invalid_credentials)` — which tells a cashier nothing about what to
/// do next.
class AuthErrorMapper {
  const AuthErrorMapper._();

  static const String genericFailure =
      'Could not sign you in. Please try again.';

  static const String offline =
      'No internet connection. Check your network and try again.';

  static const String invalidCredentials =
      'Email or password is incorrect. Check them and try again, or tap '
      '"Send a magic link" to sign in without a password.';

  /// Network failures we want to report as "offline" rather than as a bug.
  /// Matched by type name so this file stays free of `dart:io`, which is not
  /// available on the web target.
  static const Set<String> _networkErrorTypes = {
    'SocketException',
    'HttpException',
    'ClientException',
    'HandshakeException',
  };

  /// The message to show the user for [error].
  ///
  /// [fallback] is the copy used when the error carries nothing we can
  /// translate; pass one that fits the screen the error surfaced on.
  static String message(Object error, {String fallback = genericFailure}) {
    // `AuthRetryableFetchException` extends `AuthException`, so it has to be
    // checked before the general auth branch below.
    if (error is AuthRetryableFetchException) return offline;
    if (error is TimeoutException) return offline;
    if (_networkErrorTypes.contains(error.runtimeType.toString())) {
      return offline;
    }
    if (error is AuthException) return _fromAuthException(error, fallback);
    return fallback;
  }

  static String _fromAuthException(AuthException error, String fallback) {
    switch (error.code) {
      case 'invalid_credentials':
      case 'invalid_grant':
        return invalidCredentials;
      case 'email_not_confirmed':
        return 'Your email has not been confirmed yet. Open the confirmation '
            'link we emailed you, then sign in again.';
      case 'user_not_found':
        return 'No account found for this email. Ask your manager to invite '
            'you to the shop.';
      case 'email_address_invalid':
      case 'validation_failed':
        return 'That email address does not look right. Check it for typos '
            'and try again.';
      case 'user_banned':
        return 'This account has been disabled. Contact your manager.';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Too many attempts. Please wait a minute and try again.';
      case 'otp_expired':
        return 'That sign-in link has expired. Request a new one.';
      case 'signup_disabled':
        return 'New sign-ups are disabled. Ask your manager to invite you to '
            'the shop.';
      case 'weak_password':
        return 'That password is too weak. Choose a longer one.';
      case 'session_not_found':
      case 'session_expired':
        return 'Your session expired. Please sign in again.';
    }

    if (error is AuthSessionMissingException) {
      return 'Your session expired. Please sign in again.';
    }

    // Self-hosted or older GoTrue builds may omit `code`; fall back to the
    // server message for the one case cashiers hit most.
    if (error.message.toLowerCase().contains('invalid login credentials')) {
      return invalidCredentials;
    }

    final status = int.tryParse(error.statusCode ?? '');
    if (status != null && status >= 500) {
      return 'Sign-in is temporarily unavailable. Please try again in a '
          'moment.';
    }

    return fallback;
  }
}
