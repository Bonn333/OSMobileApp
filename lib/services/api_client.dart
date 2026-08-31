import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/backend_info.dart';
import '../models/device_with_shockers.dart';
import '../models/login_request.dart';
import '../models/self_user.dart';
import '../models/shared_user.dart';
import '../utils/logger.dart';

class ApiClient {
  static const String defaultBaseUrl = 'https://api.openshock.app';

  /// OpenShock requires every request to carry a meaningful User-Agent.
  /// Requests without one are rejected at the edge by Cloudflare with a 403
  /// and an HTML body, long before they reach the API.
  static const String userAgent = 'OpenShockMobile/1.0.0';

  /// Name of the session cookie the API sets on a successful login. It matches
  /// the `UserSessionCookie` security scheme in the OpenAPI document.
  static const String sessionCookieName = 'openShockSession';

  static const _cookieStorageKey = 'session_cookies';
  static const _tag = 'ApiClient';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  late Dio _dio;
  late CookieJar _cookieJar;

  String _baseUrl;
  bool _initialized = false;

  /// Shared instance, so every caller sees the same session.
  static final ApiClient _shared = ApiClient._internal();

  factory ApiClient() => _shared;

  ApiClient._internal() : _baseUrl = defaultBaseUrl;

  String get baseUrl => _baseUrl;

  Future<CookieJar> get cookieJar async {
    await _ensureInitialized();
    return _cookieJar;
  }

  Future<void> setBaseUrl(String baseUrl) async {
    _baseUrl = baseUrl;

    // If already initialized, we need to reinitialize Dio with the new base URL
    if (_initialized) {
      _initializeDio();
      await _loadCookiesFromSecureStorage();
    } else {
      await _ensureInitialized();
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    _cookieJar = CookieJar();
    _initializeDio();
    await _loadCookiesFromSecureStorage();
    _initialized = true;
  }

  void _initializeDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        validateStatus: (status) => status != null && status < 500,
        headers: {'User-Agent': userAgent},
      ),
    );

    // The cookie manager carries the session cookie on every request.
    _dio.interceptors.add(CookieManager(_cookieJar));
  }

  // -------------------------
  // Cookies (secure storage)
  // -------------------------

  Future<void> _loadCookiesFromSecureStorage() async {
    try {
      final cookiesJson = await _secureStorage.read(key: _cookieStorageKey);
      if (cookiesJson == null || cookiesJson.isEmpty) return;

      final decoded = jsonDecode(cookiesJson);
      if (decoded is! List) return;

      final uri = Uri.parse(_baseUrl);
      final cookies = decoded
          .whereType<Map<String, dynamic>>()
          .map(_cookieFromJson)
          .toList();

      await _cookieJar.saveFromResponse(uri, cookies);
      Logger.log('Loaded ${cookies.length} cookies from storage', tag: _tag);
    } catch (e, stackTrace) {
      Logger.error(
        'Failed to load cookies',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _saveCookiesToSecureStorage() async {
    try {
      final uri = Uri.parse(_baseUrl);
      final cookies = await _cookieJar.loadForRequest(uri);

      if (cookies.isEmpty) {
        await _secureStorage.delete(key: _cookieStorageKey);
        return;
      }

      await _secureStorage.write(
        key: _cookieStorageKey,
        value: jsonEncode(cookies.map(_cookieToJson).toList()),
      );
      Logger.log('Saved ${cookies.length} cookies to storage', tag: _tag);
    } catch (e, stackTrace) {
      Logger.error(
        'Failed to save cookies',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Cookie _cookieFromJson(Map<String, dynamic> json) {
    return Cookie(json['name'] as String? ?? '', json['value'] as String? ?? '')
      ..domain = json['domain'] as String?
      ..path = json['path'] as String?
      ..expires = (json['expires'] is String)
          ? DateTime.tryParse(json['expires'] as String)
          : null
      ..secure = json['secure'] as bool? ?? false
      ..httpOnly = json['httpOnly'] as bool? ?? false;
  }

  Map<String, dynamic> _cookieToJson(Cookie cookie) => {
    'name': cookie.name,
    'value': cookie.value,
    'domain': cookie.domain,
    'path': cookie.path,
    'expires': cookie.expires?.toIso8601String(),
    'secure': cookie.secure,
    'httpOnly': cookie.httpOnly,
  };

  /// Value of the session cookie, used to authenticate the SignalR hub.
  Future<String?> getSessionKey() async {
    await _ensureInitialized();

    try {
      final cookies = await _cookieJar.loadForRequest(Uri.parse(_baseUrl));
      for (final cookie in cookies) {
        if (cookie.name == sessionCookieName && cookie.value.isNotEmpty) {
          return cookie.value;
        }
      }
      return null;
    } catch (e, stackTrace) {
      Logger.error(
        'Failed to read session key',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  // -------------------------
  // API calls
  // -------------------------

  /// `GET /1` - unauthenticated metadata, including the Turnstile site key the
  /// login screen needs. Fetched at runtime rather than hardcoded so that a
  /// self-hosted instance supplies its own key, or none when it is disabled.
  Future<ApiResponse<BackendInfo>> getBackendInfo() async {
    await _ensureInitialized();

    try {
      final response = await _dio.get('/1');

      if (response.statusCode == 200) {
        final data = _extractData(response.data);
        if (data == null) {
          return ApiResponse.error('Unexpected response format');
        }
        return ApiResponse.success(BackendInfo.fromJson(data));
      }

      return ApiResponse.error(
        _apiMessage(
          response,
          fallback: 'Failed to load server info: ${response.statusCode}',
        ),
      );
    } on DioException catch (e) {
      Logger.error('Backend info DioException', tag: _tag, error: e);
      return ApiResponse.error(_handleDioError(e));
    } catch (e, stackTrace) {
      Logger.error(
        'Backend info error',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return ApiResponse.error('An unexpected error occurred');
    }
  }

  /// `POST /2/account/login`. On success the server sets the session cookie,
  /// which the cookie manager stores and we persist to secure storage.
  Future<ApiResponse<void>> login(LoginRequest request) async {
    await _ensureInitialized();

    try {
      final response = await _dio.post(
        '/2/account/login',
        data: request.toJson(),
      );

      Logger.log('Login response status: ${response.statusCode}', tag: _tag);

      if (response.statusCode == 200) {
        await _saveCookiesToSecureStorage();
        return ApiResponse.success(null);
      }

      if (response.statusCode == 401) {
        return ApiResponse.error('Invalid username/email or password');
      }

      // The API distinguishes a failed captcha from a plain rejection through
      // the `type` field, so say which one it was.
      if (response.statusCode == 403) {
        final type = _errorType(response);
        if (type != null && type.startsWith('Turnstile')) {
          return ApiResponse.error(
            'Captcha verification failed. Please try again.',
          );
        }
        return ApiResponse.error(
          _apiMessage(response, fallback: 'Access forbidden'),
        );
      }

      // 410 means this client is calling an endpoint the server has retired.
      if (response.statusCode == 410) {
        return ApiResponse.error(
          _apiMessage(
            response,
            fallback: 'This app is out of date and must be updated.',
          ),
        );
      }

      return ApiResponse.error(
        _apiMessage(response, fallback: 'Login failed: ${response.statusCode}'),
      );
    } on DioException catch (e) {
      Logger.error('Login DioException', tag: _tag, error: e);
      return ApiResponse.error(_handleDioError(e));
    } catch (e, stackTrace) {
      Logger.error('Login error', tag: _tag, error: e, stackTrace: stackTrace);
      return ApiResponse.error('An unexpected error occurred: $e');
    }
  }

  /// `POST /1/account/logout` - invalidates the session server-side.
  Future<ApiResponse<void>> logout() async {
    await _ensureInitialized();

    try {
      final response = await _dio.post('/1/account/logout');
      await _cookieJar.deleteAll();
      await _secureStorage.delete(key: _cookieStorageKey);

      if (response.statusCode == 200) {
        return ApiResponse.success(null);
      }
      return ApiResponse.error(
        _apiMessage(response, fallback: 'Logout failed: ${response.statusCode}'),
      );
    } on DioException catch (e) {
      // The local session is dropped either way, so a failure is not fatal.
      await _cookieJar.deleteAll();
      await _secureStorage.delete(key: _cookieStorageKey);
      return ApiResponse.error(_handleDioError(e));
    }
  }


  Future<ApiResponse<SelfUser>> getSelf() async {
    await _ensureInitialized();

    try {
      Logger.log('Fetching self user', tag: _tag);
      final response = await _dio.get('/1/users/self');

      if (response.statusCode == 200) {
        final data = _extractData(response.data);
        if (data == null) {
          Logger.error('Unexpected response format for self user', tag: _tag);
          return ApiResponse.error('Unexpected response format');
        }

        final selfUser = SelfUser.fromJson(data);
        Logger.log('Loaded self user: ${selfUser.name}', tag: _tag);
        return ApiResponse.success(selfUser);
      }

      if (response.statusCode == 401) {
        Logger.error('Unauthorized when fetching self user', tag: _tag);
        return ApiResponse.error('Unauthorized - please login again');
      }

      Logger.error(
        'Failed to load self user: ${response.statusCode}',
        tag: _tag,
      );
      return ApiResponse.error(
        _apiMessage(
          response,
          fallback: 'Failed to load self user: ${response.statusCode}',
        ),
      );
    } on DioException catch (e) {
      Logger.error(
        'Get self user DioException',
        tag: _tag,
        error: e,
        stackTrace: e.stackTrace,
      );
      return ApiResponse.error(_handleDioError(e));
    } catch (e, stackTrace) {
      Logger.error(
        'Get self user error',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return ApiResponse.error('An unexpected error occurred');
    }
  }

  Future<ApiResponse<List<DeviceWithShockers>>> getOwnShockers() async {
    await _ensureInitialized();

    try {
      Logger.log('Fetching own shockers', tag: _tag);
      final response = await _dio.get('/1/shockers/own');

      if (response.statusCode == 200) {
        final data = _extractListData(response.data);
        if (data == null) {
          Logger.error(
            'Unexpected response format for own shockers',
            tag: _tag,
          );
          return ApiResponse.error('Unexpected response format');
        }

        final devices = data
            .whereType<Map<String, dynamic>>()
            .map(DeviceWithShockers.fromJson)
            .toList();

        Logger.log('Loaded ${devices.length} devices with shockers', tag: _tag);
        return ApiResponse.success(devices);
      }

      if (response.statusCode == 401) {
        Logger.error('Unauthorized when fetching shockers', tag: _tag);
        return ApiResponse.error('Unauthorized - please login again');
      }

      Logger.error(
        'Failed to load shockers: ${response.statusCode}',
        tag: _tag,
      );
      return ApiResponse.error(
        _apiMessage(
          response,
          fallback: 'Failed to load shockers: ${response.statusCode}',
        ),
      );
    } on DioException catch (e) {
      Logger.error(
        'Get own shockers DioException',
        tag: _tag,
        error: e,
        stackTrace: e.stackTrace,
      );
      return ApiResponse.error(_handleDioError(e));
    } catch (e, stackTrace) {
      Logger.error(
        'Get own shockers error',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return ApiResponse.error('An unexpected error occurred');
    }
  }

  Future<ApiResponse<List<SharedUser>>> getSharedShockers() async {
    await _ensureInitialized();

    try {
      Logger.log('Fetching shared shockers', tag: _tag);
      final response = await _dio.get('/1/shockers/shared');

      if (response.statusCode == 200) {
        final data = _extractListData(response.data);
        if (data == null) {
          Logger.error(
            'Unexpected response format for shared shockers',
            tag: _tag,
          );
          return ApiResponse.error('Unexpected response format');
        }

        final sharedUsers = data
            .whereType<Map<String, dynamic>>()
            .map(SharedUser.fromJson)
            .toList();

        Logger.log(
          'Loaded ${sharedUsers.length} shared users with shockers',
          tag: _tag,
        );
        return ApiResponse.success(sharedUsers);
      }

      if (response.statusCode == 401) {
        Logger.error('Unauthorized when fetching shared shockers', tag: _tag);
        return ApiResponse.error('Unauthorized - please login again');
      }

      Logger.error(
        'Failed to load shared shockers: ${response.statusCode}',
        tag: _tag,
      );
      return ApiResponse.error(
        _apiMessage(
          response,
          fallback: 'Failed to load shared shockers: ${response.statusCode}',
        ),
      );
    } on DioException catch (e) {
      Logger.error(
        'Get shared shockers DioException',
        tag: _tag,
        error: e,
        stackTrace: e.stackTrace,
      );
      return ApiResponse.error(_handleDioError(e));
    } catch (e, stackTrace) {
      Logger.error(
        'Get shared shockers error',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      return ApiResponse.error('An unexpected error occurred');
    }
  }

  // -------------------------
  // Helpers
  // -------------------------

  Map<String, dynamic>? _extractData(dynamic responseData) {
    if (responseData is Map<String, dynamic> &&
        responseData.containsKey('data')) {
      final data = responseData['data'];
      if (data is Map<String, dynamic>) return data;
    }

    return null;
  }

  List<dynamic>? _extractListData(dynamic responseData) {
    if (responseData is List<dynamic>) return responseData;

    if (responseData is Map<String, dynamic>) {
      final data = responseData['data'];
      if (data is List<dynamic>) return data;
    }

    return null;
  }

  /// OpenShock returns RFC 7807 style errors carrying `detail` / `message` and
  /// a machine-readable `type`. Prefer those over `statusMessage`, which is
  /// usually empty over HTTP/2 and produced useless text like "Login failed: ".
  ///
  /// Falls back gracefully when the body is not JSON at all - a Cloudflare
  /// block, for instance, answers with an HTML page.
  String _apiMessage(Response<dynamic> response, {required String fallback}) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      for (final key in const ['detail', 'message', 'title']) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
      }
    }
    return fallback;
  }

  /// Machine-readable error discriminator, e.g. `Turnstile.Invalid`. Used to
  /// tell a failed captcha apart from an ordinary rejection, since both are 403.
  String? _errorType(Response<dynamic> response) {
    final data = response.data;
    if (data is Map<String, dynamic>) {
      final type = data['type'];
      if (type is String && type.isNotEmpty) return type;
    }
    return null;
  }

  String _handleDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timeout. Please check your internet connection.';
      case DioExceptionType.connectionError:
        return 'Cannot connect to server. Please check your internet connection.';
      case DioExceptionType.badResponse:
        return 'Server error: ${e.response?.statusMessage ?? 'Unknown error'}';
      case DioExceptionType.cancel:
        return 'Request cancelled';
      default:
        return 'Network error occurred';
    }
  }
}

class ApiResponse<T> {
  final T? data;
  final String? error;
  final bool isSuccess;

  ApiResponse._({this.data, this.error, required this.isSuccess});

  factory ApiResponse.success(T? data) {
    return ApiResponse._(data: data, isSuccess: true);
  }

  factory ApiResponse.error(String error) {
    return ApiResponse._(error: error, isSuccess: false);
  }
}
