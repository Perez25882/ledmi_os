import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'session_manager.dart';
import 'supabase_client.dart';

class AuthService {
  final _supabase = SupabaseClientManager.client;
  StreamSubscription<AuthState>? _authSub;
  final _reLoginController = StreamController<void>.broadcast();

  AuthService() {
    // The supabase_flutter SDK (v2.16) does not emit a dedicated
    // `tokenRefreshFailed` event. When the refresh token is rejected, it emits
    // `signedOut` with `signOutReason` set to `sessionExpired`/`sessionMissing`.
    // We use that to implement the SYNC_PROTOCOL §3.2 fallback.
    _authSub = _supabase.auth.onAuthStateChange.listen(
      _onAuthStateChange,
      onError: (Object error, StackTrace stack) {
        // A token refresh attempt can also surface here on networks with no
        // connectivity. Treat any auth-stream error as a re-login requirement so
        // sync stops and the queue is preserved until the cashier re-auths.
        _handleTokenRefreshFailure();
      },
    );
  }

  Stream<AuthState> get onAuthStateChange => _supabase.auth.onAuthStateChange;

  /// Emits when a token refresh fails and the cashier must re-authenticate
  /// (SYNC_PROTOCOL §3.2). Sync is stopped and the offline queue is preserved.
  Stream<void> get reLoginRequired => _reLoginController.stream;

  User? get currentUser => _supabase.auth.currentUser;

  Session? get currentSession => _supabase.auth.currentSession;

  bool get isAuthenticated => currentSession != null && currentUser != null;

  void _onAuthStateChange(AuthState state) {
    if (state.event == AuthChangeEvent.signedIn) {
      SessionManager.clearReLoginRequired();
      return;
    }

    if (state.event == AuthChangeEvent.signedOut) {
      final reason = state.signOutReason;
      if (reason == SignOutReason.sessionExpired ||
          reason == SignOutReason.sessionMissing) {
        _handleTokenRefreshFailure();
      }
    }
  }

  /// SYNC_PROTOCOL §3.2 fallback: stop sync, surface re-login signal, preserve
  /// the offline queue.
  void _handleTokenRefreshFailure() {
    SessionManager.markReLoginRequired();
    // Clear sensitive session context but keep the offline queue (separate box)
    // so pending sales/refunds survive re-authentication.
    SessionManager.clearSensitiveData();
    _reLoginController.add(null);
  }

  Future<AuthResponse> signIn({required String email, required String password}) {
    return _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sends a magic link (passwordless OTP) sign-in email. Supabase delivers
  /// an email containing a link that completes the PKCE flow and establishes
  /// a session — the existing `onAuthStateChange` listener picks it up.
  Future<void> signInWithMagicLink(String email) {
    return _supabase.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: 'io.supabase.flutter://login-callback/',
    );
  }

  Future<void> signOut() => _supabase.auth.signOut();

  void dispose() {
    _authSub?.cancel();
    _reLoginController.close();
  }
}
