import 'package:flutter/foundation.dart';

import '../models/login_request.dart';
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
      final cookieJar = await _apiClient.cookieJar;
      final cookies = await cookieJar.loadForRequest(
        Uri.parse(_apiClient.baseUrl),
      );

      if (cookies.isEmpty) {
        Logger.log('No stored session, user needs to sign in', tag: _tag);
        _setState(AuthState.unauthenticated);
        return;
      }

      Logger.log('Found stored session, validating it', tag: _tag);
      final selfResponse = await _apiClient.getSelf();
      if (selfResponse.isSuccess && selfResponse.data != null) {
        Logger.log('Session is valid, user authenticated', tag: _tag);
        _selfUser = selfResponse.data;
        _setState(AuthState.authenticated);
        return;
      }

      Logger.log('Stored session is no longer valid', tag: _tag);
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

  Future<bool> loginWithCredentials(
    String usernameOrEmail,
    String password, {
    required String turnstileResponse,
  }) async {
    final identifier = usernameOrEmail.trim();

    Logger.log('loginWithCredentials called', tag: _tag);
    _setState(AuthState.loading, clearError: true);

    if (identifier.isEmpty || password.isEmpty) {
      _error = 'Please enter your username and password';
      _setState(AuthState.unauthenticated);
      return false;
    }

    if (turnstileResponse.isEmpty) {
      _error = 'Please complete the captcha first';
      _setState(AuthState.unauthenticated);
      return false;
    }

    try {
      final loginResponse = await _apiClient.login(
        LoginRequest(
          usernameOrEmail: identifier,
          password: password,
          turnstileResponse: turnstileResponse,
        ),
      );

      if (!loginResponse.isSuccess) {
        _error = loginResponse.error;
        Logger.error('Login failed: $_error', tag: _tag);
        _setState(AuthState.unauthenticated);
        return false;
      }

      final selfResponse = await _apiClient.getSelf();
      if (!selfResponse.isSuccess || selfResponse.data == null) {
        _error = selfResponse.error ?? 'Failed to fetch user data';
        Logger.error('Failed to fetch self user data', tag: _tag);
        _setState(AuthState.unauthenticated);
        return false;
      }

      _selfUser = selfResponse.data;
      Logger.log('Login successful', tag: _tag);
      _setState(AuthState.authenticated);
      return true;
    } catch (e, stackTrace) {
      _error = 'Login failed: $e';
      Logger.error(
        'Login exception: $_error',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      _setState(AuthState.unauthenticated);
      return false;
    }
  }

  Future<void> logout() async {
    Logger.log('Logging out user', tag: _tag);
    _setState(AuthState.loading, clearError: true);

    try {
      await _apiClient.logout();
    } catch (e) {
      Logger.log('Logout API call failed, clearing locally', tag: _tag);
    }

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
