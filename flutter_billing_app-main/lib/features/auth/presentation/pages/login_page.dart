import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/supabase/auth_error.dart';
import '../../../../core/supabase/auth_service.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/app_validators.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _magicLinkMode = false;
  bool _magicLinkSent = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final email = _emailController.text.trim();
    // The password is sent verbatim: trimming it silently changes what the
    // cashier typed and turns a valid password into "invalid credentials".
    final password = _passwordController.text;

    final emailError = AppValidators.email(email);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Please enter your password');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _authService.signIn(email: email, password: password);
      if (!mounted) return;
      context.go('/branch-selection');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthErrorMapper.message(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMagicLink() async {
    final email = _emailController.text.trim();

    final emailError = AppValidators.email(email);
    if (emailError != null) {
      setState(() => _error = emailError);
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _authService.signInWithMagicLink(email);
      if (!mounted) return;
      setState(() {
        _magicLinkSent = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthErrorMapper.message(e);
        _isLoading = false;
      });
    }
  }

  void _toggleMode() {
    setState(() {
      _magicLinkMode = !_magicLinkMode;
      _error = null;
      _magicLinkSent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top accent bar
            Container(height: 6, color: AppTheme.primary),
            // Logo section
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Column(
                children: [
                  // Logo box
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'L',
                        style: TextStyle(
                          color: AppTheme.primaryForeground,
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'LedgerMind POS',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.foreground,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Smart retail checkout for Africa',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            // Form card
            Padding(
              padding: const EdgeInsets.only(top: 40, left: 32, right: 32),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Email',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.foreground,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        hintText: 'cashier@store.gh',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.none,
                      textInputAction: _magicLinkMode
                          ? TextInputAction.done
                          : TextInputAction.next,
                      onSubmitted: (_) {
                        if (_magicLinkMode && !_isLoading) _sendMagicLink();
                      },
                    ),
                    if (!_magicLinkMode) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Password',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.foreground,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          hintText:
                              '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                              color: AppTheme.mutedForeground,
                            ),
                            tooltip: _obscurePassword
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                        ),
                        obscureText: _obscurePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) {
                          if (!_isLoading) _signIn();
                        },
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.destructive.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.destructive.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppTheme.destructive,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: AppTheme.destructive,
                                  fontSize: 13,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (_magicLinkMode && _magicLinkSent) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.mark_email_read_outlined,
                                color: AppTheme.primary, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Check your email for a sign-in link',
                                style: TextStyle(
                                  color: AppTheme.accentForeground,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading
                            ? null
                            : (_magicLinkMode ? _sendMagicLink : _signIn),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: AppTheme.primaryForeground,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          shadowColor: AppTheme.primary.withValues(alpha: 0.3),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.primaryForeground,
                                ),
                              )
                            : Text(
                                _magicLinkMode ? 'Send Link' : 'Sign In',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton(
                        onPressed: _toggleMode,
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                        ),
                        child: Text(
                          _magicLinkMode
                              ? 'Use password instead'
                              : 'Send a magic link',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            // Footer
            const Padding(
              padding: EdgeInsets.only(bottom: 32),
              child: Text(
                'Powered by LedgerMind OS',
                style: TextStyle(
                  fontSize: 11,
                  color: AppTheme.mutedForeground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
