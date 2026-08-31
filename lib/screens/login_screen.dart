import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';
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
  static const _apiTokensUrl = 'https://openshock.app/settings/api-tokens';

  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  final _customHostController = TextEditingController();

  bool _showAdvanced = false;
  bool _obscureToken = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDefaultHost();
  }

  Future<void> _loadDefaultHost() async {
    final authProvider = context.read<AuthProvider>();
    _customHostController.text = authProvider.currentHost;
  }

  @override
  void dispose() {
    _tokenController.dispose();
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

  Future<void> _handleLogin() async {
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    Logger.log('Starting sign-in process', tag: 'LoginScreen');
    _setLoading(true);

    // Show loading snackbar
    CustomSnackbar.loading(
      context,
      title: 'Signing In',
      description: 'Please wait...',
      key: 'login',
    );

    final authProvider = context.read<AuthProvider>();

    // Update custom host if advanced settings are shown and URL is provided
    if (_showAdvanced && _customHostController.text.trim().isNotEmpty) {
      final customUrl = _customHostController.text.trim();
      if (customUrl != authProvider.currentHost) {
        Logger.log('Updating custom host from login screen', tag: 'LoginScreen');
        await authProvider.setCustomHost(customUrl);
      }
    }

    final success = await authProvider.loginWithToken(_tokenController.text);

    _setLoading(false);
    if (!mounted) return;

    // Dismiss loading snackbar
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

    Logger.error('Sign-in failed, showing error to user', tag: 'LoginScreen');
    CustomSnackbar.error(
      context,
      title: 'Sign In Failed',
      description: authProvider.error ?? 'Please check your API token',
    );
  }

  Future<void> _handleBack() async {
    Logger.log('User navigating back to onboarding', tag: 'LoginScreen');
    await StorageService().setOnboardingComplete(false);
    if (!mounted) return;
    Navigator.of(context).pop();
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
                    'Sign in with an OpenShock API token',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(height: 40),

                  // API token
                  TextFormField(
                    controller: _tokenController,
                    style: const TextStyle(color: Colors.white),
                    obscureText: _obscureToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: _inputDecoration(
                      labelText: 'API Token',
                      prefixIcon: Icons.key,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureToken
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.white70,
                        ),
                        onPressed: () =>
                            setState(() => _obscureToken = !_obscureToken),
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'Please enter your API token';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Where to get a token
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.blue.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              color: Colors.white70,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Where do I get a token?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create one under Settings → API Tokens on the '
                          'OpenShock website, then paste it above.',
                          style: TextStyle(
                            color: Colors.blue.shade100,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          _apiTokensUrl,
                          style: TextStyle(
                            color: Colors.blue.shade200,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

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

                  // Sign in button
                  ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
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
