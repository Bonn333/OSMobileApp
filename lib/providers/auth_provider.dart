import 'package:flutter/foundation.dart';

import '../models/self_user.dart';
import '../services/api_client.dart';
import '../services/storage_service.dart';
import '../utils/logger.dart';

enum AuthState { initial, loading, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  static const _tag = 'AuthProvider';

  final ApiClient _apiClient;
  final StorageService _storageService;

  AuthState _authState = AuthState.initial;
  String? _error;
  SelfUser? _selfUser;

  AuthProvider({
    required ApiClient apiClient,
    required StorageService storageService,
  }) : _apiClient = apiClient,
       _storageService = storageService;

  AuthState get authState => _authState;
  String? get error => _error;
  bool get isAuthenticated => _authState == AuthState.authenticated;
  bool get isLoading => _authState == AuthState.loading;
  SelfUser? get selfUser => _selfUser;

  String get currentHost => _apiClient.baseUrl;

  Future<void> initialize() async {
    Logger.log('Initializing authentication', tag: _tag);
    _setState(AuthState.loading, clearError: true);

    try {
      await _applyStoredHostIfAny();

      final token = await _storageService.getApiToken();
      if (token == null) {
        Logger.log('No stored API token, user needs to sign in', tag: _tag);
        _setState(AuthState.unauthenticated);
        return;
      }

      Logger.log('Found stored API token, validating it', tag: _tag);
      await _apiClient.setApiToken(token);

      final selfResponse = await _apiClient.getSelf();
      if (selfResponse.isSuccess && selfResponse.data != null) {
        Logger.log('Token is valid, user authenticated', tag: _tag);
        _selfUser = selfResponse.data;
        _setState(AuthState.authenticated);
        return;
      }

      // The token was revoked or has expired; drop it so the user is not shown
      // a stale signed-in state that fails on the next request.
      Logger.log('Stored API token is no longer valid, clearing', tag: _tag);
      await _apiClient.setApiToken(null);
      await _storageService.clearSecrets();
      _setState(AuthState.unauthenticated);
    } catch (e, stackTrace) {
      _error = 'Failed to initialize: $e';
      Logger.error(
        'Initialization failed',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      _setState(AuthState.unauthenticated);
    }
  }

  /// Sign in with an API token created at
  /// <https://openshock.app/settings/api-tokens>.
  ///
  /// Password sign-in is not available to this app: `POST /1/account/login` was
  /// retired (410 Gone) and its replacement `POST /2/account/login` requires a
  /// Cloudflare Turnstile token, which a native client cannot produce without
  /// embedding a captcha webview. API tokens are the authentication method the
  /// OpenShock developer documentation points third-party clients at.
  Future<bool> loginWithToken(String apiToken) async {
    final trimmedToken = apiToken.trim();

    Logger.log('loginWithToken called', tag: _tag);
    _setState(AuthState.loading, clearError: true);

    if (trimmedToken.isEmpty) {
      _error = 'Please enter an API token';
      _setState(AuthState.unauthenticated);
      return false;
    }

    try {
      await _apiClient.setApiToken(trimmedToken);

      // The token is only proven good once an authenticated call succeeds.
      Logger.log('Validating token via self user lookup', tag: _tag);
      final selfResponse = await _apiClient.getSelf();

      if (!selfResponse.isSuccess || selfResponse.data == null) {
        _error = selfResponse.error ?? 'Failed to fetch user data';
        Logger.error('Token validation failed: $_error', tag: _tag);
        await _apiClient.setApiToken(null);
        _setState(AuthState.unauthenticated);
        return false;
      }

      _selfUser = selfResponse.data;
      await _storageService.saveApiToken(trimmedToken);

      Logger.log('Sign-in successful', tag: _tag);
      _setState(AuthState.authenticated);
      return true;
    } catch (e, stackTrace) {
      _error = 'Sign-in failed: $e';
      Logger.error(
        'Sign-in exception: $_error',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      await _apiClient.setApiToken(null);
      _setState(AuthState.unauthenticated);
      return false;
    }
  }

  Future<void> logout() async {
    Logger.log('Logging out user', tag: _tag);
    _setState(AuthState.loading, clearError: true);

    // Nothing to invalidate server-side: the token stays valid until the user
    // revokes it on the website, so signing out just forgets it locally.
    await _apiClient.setApiToken(null);
    await _storageService.clearSecrets();

    _selfUser = null;
    Logger.log('Logout complete', tag: _tag);
    _setState(AuthState.unauthenticated, clearError: true);
  }

  Future<void> setCustomHost(String host) async {
    final trimmed = host.trim();
    Logger.log('Setting custom host: $trimmed', tag: _tag);

    await _storageService.saveCustomHost(trimmed);
    await _apiClient.setBaseUrl(trimmed);
  }

  Future<void> _applyStoredHostIfAny() async {
    final customHost = await _storageService.getCustomHost();
    if (customHost == null || customHost.isEmpty) return;

    Logger.log('Using custom host: $customHost', tag: _tag);
    await _apiClient.setBaseUrl(customHost);
  }

  void _setState(AuthState state, {bool clearError = false}) {
    _authState = state;
    if (clearError) _error = null;
    notifyListeners();
  }
}
