import 'dart:async';

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/backend_info.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../utils/logger.dart';
import '../utils/validators.dart';
import '../widgets/custom_snackbar.dart';
import 'overview_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _bgColor = Color(0xFF0A0A0A);
  static const _pagePadding = EdgeInsets.all(24);

  /// Sent when Turnstile is disabled; the API still requires a non-empty value.
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

  int _turnstileEpoch = 0;
  String? _turnstileError;
  Timer? _turnstileWatchdog;

  @override
  void initState() {
    super.initState();
    _customHostController.text = context.read<AuthProvider>().currentHost;
    _loadBackendInfo();
  }

  Future<void> _loadBackendInfo() async {
    _turnstileWatchdog?.cancel();
    setState(() {
      _loadingBackendInfo = true;
      _backendInfoError = null;
      _turnstileToken = null;
      _turnstileError = null;
    });

    final response = await ApiClient().getBackendInfo();
    if (!mounted) return;

    setState(() {
      _loadingBackendInfo = false;
      if (response.isSuccess && response.data != null) {
        _backendInfo = response.data;
        if (_backendInfo!.isTurnstileEnabled) {
          _startTurnstileWatchdog();
        } else {
          _turnstileToken = _turnstileDisabledPlaceholder;
        }
      } else {
        _backendInfoError = response.error ?? 'Could not reach the server';
      }
    });
  }

  @override
  void dispose() {
    _turnstileWatchdog?.cancel();
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

  bool get _canSubmit =>
      !_isLoading && _turnstileToken != null && !_hostChangePending;

  /// A token is only valid for the instance that issued it.
  bool get _hostChangePending {
    if (!_showAdvanced) return false;
    final host = _customHostController.text.trim();
    return host.isNotEmpty && host != context.read<AuthProvider>().currentHost;
  }

  Future<void> _applyHostChange() async {
    final host = _customHostController.text.trim();
    if (host.isEmpty) return;

    final authProvider = context.read<AuthProvider>();
    if (host == authProvider.currentHost) return;

    Logger.log('Applying custom host: $host', tag: 'LoginScreen');
    await authProvider.setCustomHost(host);
    if (!mounted) return;

    await _loadBackendInfo();
  }

  /// Tokens are single-use, so a failed attempt needs a new one.
  void _resetTurnstile() {
    if (_backendInfo?.isTurnstileEnabled ?? false) {
      setState(() {
        _turnstileToken = null;
        _turnstileError = null;
        _turnstileEpoch++;
      });
      _startTurnstileWatchdog();
    } else {
      setState(() => _turnstileToken = _turnstileDisabledPlaceholder);
    }
  }

  /// The widget renders itself fully transparent until the challenge reports
  /// ready, so a challenge that never loads is invisible rather than broken
  /// looking. Surface that instead of leaving a dead Sign In button.
  void _startTurnstileWatchdog() {
    _turnstileWatchdog?.cancel();
    _turnstileWatchdog = Timer(const Duration(seconds: 20), () {
      if (!mounted || _turnstileToken != null || _turnstileError != null) {
        return;
      }
      Logger.error('Turnstile did not produce a token', tag: 'LoginScreen');
      setState(() => _turnstileError = 'The captcha did not load.');
    });
  }

  void _onTurnstileError(String message) {
    Logger.error('Turnstile error: $message', tag: 'LoginScreen');
    _turnstileWatchdog?.cancel();
    if (!mounted) return;
    setState(() {
      _turnstileToken = null;
      _turnstileError = message;
    });
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

    final success = await authProvider.loginWithCredentials(
      _identifierController.text,
      _passwordController.text,
      turnstileResponse: token,
    );

    _setLoading(false);
    if (!mounted) return;

    CustomSnackbar.dismiss('login');

    if (success) {
      Logger.log(
        'Sign-in successful, navigating to overview',
        tag: 'LoginScreen',
      );
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

  void _handleBack() {
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
      return const SizedBox.shrink();
    }

    if (_turnstileError != null) {
      return _turnstileErrorCard(_turnstileError!);
    }

    return Center(
      child: CloudflareTurnstile(
        key: ValueKey(_turnstileEpoch),
        siteKey: info.turnstileSiteKey!,
        action: 'signin',
        // Turnstile checks this origin against the domains allowed for the key.
        baseUrl: info.frontendUrl ?? ApiClient().baseUrl,
        options: TurnstileOptions(
          theme: TurnstileTheme.dark,
          size: TurnstileSize.flexible,
        ),
        onTokenReceived: (token) {
          _turnstileWatchdog?.cancel();
          if (!mounted) return;
          Logger.log('Turnstile token received', tag: 'LoginScreen');
          setState(() {
            _turnstileToken = token;
            _turnstileError = null;
          });
        },
        onTokenExpired: () {
          if (!mounted) return;
          setState(() => _turnstileToken = null);
        },
        onError: (error) =>
            _onTurnstileError('${error.message} (code ${error.code})'),
        onTimeout: () => _onTurnstileError('The captcha timed out.'),
      ),
    );
  }

  Widget _turnstileErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: Colors.orange.shade100, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in needs the captcha. You can retry, or use the website.',
            style: TextStyle(color: Colors.orange.shade200, fontSize: 11),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _resetTurnstile,
              child: const Text('Retry captcha'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.of(context).canPop();

    return Scaffold(
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
                  validator: validateUsernameOrEmail,
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
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: validatePassword,
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
                    onChanged: (_) => setState(() {}),
                    onFieldSubmitted: (_) => _applyHostChange(),
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
    );
  }
}
