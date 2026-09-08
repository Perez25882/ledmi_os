import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:billing_app/core/supabase/auth_error.dart';
import 'package:billing_app/core/utils/app_validators.dart';

void main() {
  group('AuthErrorMapper.message', () {
    test('never leaks the raw exception object to the user', () {
      // The exact failure seen on the shop floor: the login screen rendered
      // "AuthApiException(message: Invalid login credentials, statusCode: 400,
      // code: invalid_credentials)".
      final error = AuthApiException(
        'Invalid login credentials',
        statusCode: '400',
        code: 'invalid_credentials',
      );

      final message = AuthErrorMapper.message(error);

      expect(message, AuthErrorMapper.invalidCredentials);
      expect(message, isNot(contains('AuthApiException')));
      expect(message, isNot(contains('statusCode')));
    });

    test('falls back to the server message when code is absent', () {
      final error = AuthApiException(
        'Invalid login credentials',
        statusCode: '400',
      );

      expect(AuthErrorMapper.message(error), AuthErrorMapper.invalidCredentials);
    });

    test('maps unconfirmed email to a next step', () {
      final error = AuthApiException(
        'Email not confirmed',
        statusCode: '400',
        code: 'email_not_confirmed',
      );

      expect(AuthErrorMapper.message(error), contains('confirmation link'));
    });

    test('maps rate limiting to a wait instruction', () {
      final error = AuthApiException(
        'Email rate limit exceeded',
        statusCode: '429',
        code: 'over_email_send_rate_limit',
      );

      expect(AuthErrorMapper.message(error), contains('Too many attempts'));
    });

    test('reports retryable fetch failures as being offline', () {
      expect(
        AuthErrorMapper.message(AuthRetryableFetchException()),
        AuthErrorMapper.offline,
      );
    });

    test('reports timeouts as being offline', () {
      expect(
        AuthErrorMapper.message(TimeoutException('no response')),
        AuthErrorMapper.offline,
      );
    });

    test('maps 5xx responses to a temporary outage', () {
      final error = AuthApiException('Internal error', statusCode: '500');

      expect(AuthErrorMapper.message(error), contains('temporarily'));
    });

    test('maps a missing session to a re-login prompt', () {
      expect(
        AuthErrorMapper.message(AuthSessionMissingException()),
        contains('session expired'),
      );
    });

    test('falls back to generic copy for unknown errors', () {
      expect(
        AuthErrorMapper.message(StateError('boom')),
        AuthErrorMapper.genericFailure,
      );
    });

    test('uses the caller fallback for untranslatable errors', () {
      const fallback = 'Could not load your branches. Please try again.';

      expect(
        AuthErrorMapper.message(StateError('boom'), fallback: fallback),
        fallback,
      );
      expect(
        AuthErrorMapper.message(
          AuthApiException('Something odd', statusCode: '400'),
          fallback: fallback,
        ),
        fallback,
      );
    });

    test('offline detection wins over the caller fallback', () {
      expect(
        AuthErrorMapper.message(
          AuthRetryableFetchException(),
          fallback: 'Could not load your branches.',
        ),
        AuthErrorMapper.offline,
      );
    });
  });

  group('AppValidators.email', () {
    test('rejects an empty email', () {
      expect(AppValidators.email(''), 'Please enter your email');
      expect(AppValidators.email(null), 'Please enter your email');
      expect(AppValidators.email('   '), 'Please enter your email');
    });

    test('rejects addresses with a dot instead of an @', () {
      expect(AppValidators.email('cashier25882.gmail.com'), isNotNull);
    });

    test('rejects addresses with no domain suffix', () {
      expect(AppValidators.email('cashier@gmail'), isNotNull);
      expect(AppValidators.email('cashier@gmail.'), isNotNull);
    });

    test('rejects addresses containing spaces', () {
      expect(AppValidators.email('cash ier@store.gh'), isNotNull);
    });

    test('accepts ordinary addresses', () {
      expect(AppValidators.email('cashier@store.gh'), isNull);
      expect(AppValidators.email('first.last+pos@store.co.uk'), isNull);
      expect(AppValidators.email('  cashier@store.gh  '), isNull);
    });
  });
}
