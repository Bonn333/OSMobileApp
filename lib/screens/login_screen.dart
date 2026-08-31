import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/backend_info.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';
import '../widgets/custom_snackbar.dart';
import '../widgets/turnstile_challenge.dart';
import 'overview_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _bgColor = Color(0xFF0A0A0A);
  static const _pagePadding = EdgeInsets.all(24);

  /// Sent when the instance reports no site key, i.e. Turnstile is disabled.
  /// The API still requires the field to be present and non-empty. This mirrors
  /// PUBLIC_TURNSTILE_DEV_BYPASS_VALUE in the official web frontend.
  static const _turnstileDisabledPlaceholder = 'INVALID';

  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _customHostController = TextEditingController();

  bool _showAdvanced = false;
  bool _obscurePassword = true;
  bool _isLoading = false;

  BackendInfo? _backendInfo;
  bool _loadingBackendInfo = true;
  String? _backendInfoError;
  String? _turnstileToken;

  // Rebuilding the challenge with a fresh key forces a new puzzle.
  int _turnstileEpoch = 0;

  @override
  void initState() {
    super.initState();
    _customHostController.text = context.read<AuthProvider>().currentHost;
    _loadBackendInfo();
  }

  /// The Turnstile site key is not hardcoded: it comes from `GET /1`, so a
  /// self-hosted instance supplies its own, or none when it is switched off.
  Future<void> _loadBackendInfo() async {
    setState(() {
      _loadingBackendInfo = true;
      _backendInfoError = null;
      _turnstileToken = null;
    });

    final response = await ApiClient().getBackendInfo();
    if (!mounted) return;

    setState(() {
      _loadingBackendInfo = false;
      if (response.isSuccess && response.data != null) {
        _backendInfo = response.data;
        // Nothing to solve when the server has Turnstile disabled.
        if (!_backendInfo!.isTurnstileEnabled) {
          _turnstileToken = _turnstileDisabledPlaceholder;
        }
      } else {
        _backendInfoError = response.error ?? 'Could not reach the server';
      }
    });
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _customHostController.dispose();
    super.dispose();
  }

  void _setLoading(bool value) {
    if (!mounted) return;
    setState(() => _isLoading = value);
  }

  InputDecoration _inputDecoration({
    required String labelText,
    required IconData prefixIcon,
    String? hintText,
    Widget? suffixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
    );

    return InputDecoration(
      labelText: labelText,
      labelStyle: const TextStyle(color: Colors.white70),
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.white30),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: const BorderSide(color: Colors.white, width: 2),
      ),
      prefixIcon: Icon(prefixIcon, color: Colors.white70),
      suffixIcon: suffixIcon,
    );
  }

  bool get _canSubmit => !_isLoading && _turnstileToken != null;

  void _resetTurnstile() {
    // A Turnstile token is single-use: once the server has seen it, the widget
    // has to be solved again before another attempt.
    if (_backendInfo?.isTurnstileEnabled ?? false) {
      setState(() {
        _turnstileToken = null;
        _turnstileEpoch++;
      });
    } else {
      setState(() => _turnstileToken = _turnstileDisabledPlaceholder);
    }
  }

  Future<void> _handleLogin() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    final token = _turnstileToken;
    if (token == null) {
      CustomSnackbar.error(
        context,
        title: 'Captcha Required',
        description: 'Please complete the captcha before signing in.',
      );
      return;
    }

    Logger.log('Starting sign-in process', tag: 'LoginScreen');
    _setLoading(true);

    CustomSnackbar.loading(
      context,
      title: 'Signing In',
      description: 'Please wait...',
      key: 'login',
    );

    final authProvider = context.read<AuthProvider>();

    if (_showAdvanced && _customHostController.text.trim().isNotEmpty) {
      final customUrl = _customHostController.text.trim();
      if (customUrl != authProvider.currentHost) {
        Logger.log('Updating custom host from login screen', tag: 'LoginScreen');
        await authProvider.setCustomHost(customUrl);
      }
    }

    final success = await authProvider.loginWithCredentials(
      _identifierController.text,
      _passwordController.text,
      turnstileResponse: token,
    );

    _setLoading(false);
    if (!mounted) return;

    CustomSnackbar.dismiss('login');

    if (success) {
      Logger.log('Sign-in successful, navigating to overview', tag: 'LoginScreen');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const OverviewScreen()),
        (route) => false,
      );
      return;
    }

    _resetTurnstile();

    Logger.error('Sign-in failed, showing error to user', tag: 'LoginScreen');
    CustomSnackbar.error(
      context,
      title: 'Sign In Failed',
      description: authProvider.error ?? 'Please check your credentials',
    );
  }

  Future<void> _handleBack() async {
    Logger.log('User navigating back to onboarding', tag: 'LoginScreen');
    await StorageService().setOnboardingComplete(false);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Widget _buildTurnstileSection() {
    if (_loadingBackendInfo) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_backendInfoError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _backendInfoError!,
                style: TextStyle(color: Colors.red.shade100, fontSize: 12),
              ),
            ),
            TextButton(onPressed: _loadBackendInfo, child: const Text('Retry')),
          ],
        ),
      );
    }

    final info = _backendInfo;
    if (info == null || !info.isTurnstileEnabled) {
      // Turnstile is disabled on this instance; nothing for the user to solve.
      return const SizedBox.shrink();
    }

    return TurnstileChallenge(
      key: ValueKey(_turnstileEpoch),
      siteKey: info.turnstileSiteKey!,
      // Turnstile checks the hostname rendering the widget against the domains
      // registered for the site key, so use the instance's own frontend origin.
      baseUrl: info.frontendUrl ?? ApiClient().baseUrl,
      onToken: (token) {
        if (!mounted) return;
        setState(() => _turnstileToken = token);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();

    return PopScope(
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          await StorageService().setOnboardingComplete(false);
        }
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          automaticallyImplyLeading: false,
          leading: canGoBack
              ? IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                  onPressed: _handleBack,
                )
              : null,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: _pagePadding,
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Image.asset(
                      'assets/os/Icon512.png',
                      width: 80,
                      height: 80,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Sign In',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enter your credentials to continue',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 40),

                  // Username or email
                  TextFormField(
                    controller: _identifierController,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: _inputDecoration(
                      labelText: 'Username or Email',
                      prefixIcon: Icons.person,
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Please enter your username or email';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passwordController,
                    style: const TextStyle(color: Colors.white),
                    obscureText: _obscurePassword,
                    decoration: _inputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icons.lock,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.white70,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  _buildTurnstileSection(),
                  const SizedBox(height: 8),

                  // Advanced Settings toggle
                  TextButton(
                    onPressed: () =>
                        setState(() => _showAdvanced = !_showAdvanced),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showAdvanced ? Icons.expand_less : Icons.expand_more,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Advanced Settings',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  if (_showAdvanced) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _customHostController,
                      style: const TextStyle(color: Colors.white),
                      decoration: _inputDecoration(
                        labelText: 'Custom Server Host',
                        prefixIcon: Icons.dns,
                        hintText: ApiClient.defaultBaseUrl,
                      ),
                      validator: (value) {
                        final v = value?.trim() ?? '';
                        if (v.isEmpty) return null;

                        final uri = Uri.tryParse(v);
                        if (uri == null || !uri.hasScheme) {
                          return 'Please enter a valid URL (e.g., https://api.example.com)';
                        }
                        return null;
                      },
                    ),
                  ],

                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: _canSubmit ? _handleLogin : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.black,
                              ),
                            ),
                          )
                        : const Text(
                            'Sign In',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
