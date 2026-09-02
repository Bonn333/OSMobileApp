import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/backend_info.dart';
import '../models/device_with_shockers.dart';
import '../models/lcg_info.dart';
import '../models/login_request.dart';
import '../models/self_user.dart';
import '../models/shared_user.dart';
import '../utils/logger.dart';

class ApiClient {
  static const String defaultBaseUrl = 'https://api.openshock.app';

  /// Required: Cloudflare rejects requests with an empty User-Agent.
  static const String userAgent = 'OpenShockMobile/1.0.0';

  static const String sessionCookieName = 'openShockSession';

  static const _cookieStorageKey = 'session_cookies';
  static const _tag = 'ApiClient';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  late Dio _dio;
  late CookieJar _cookieJar;

  String _baseUrl;
  bool _initialized = false;

  /// Shared so every caller sees the same session.
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

  /// Session cookie value, used to authenticate the SignalR hub.
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

  /// `GET /1` - server metadata, including the Turnstile site key.
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

  /// `GET /2/devices/{deviceId}/lcg` - which live control gateway to use.
  Future<ApiResponse<LcgInfo>> getLiveControlGateway(String deviceId) async {
    await _ensureInitialized();

    try {
      final response = await _dio.get('/2/devices/$deviceId/lcg');

      if (response.statusCode == 200) {
        final data = _extractObject(response.data);
        if (data == null) {
          Logger.error(
            'Unexpected LCG response: ${response.data.runtimeType}',
            tag: _tag,
          );
          return ApiResponse.error('Unexpected response format');
        }

        try {
          return ApiResponse.success(LcgInfo.fromJson(data));
        } catch (e) {
          Logger.error(
            'Could not read LCG response, keys: ${data.keys.toList()}',
            tag: _tag,
            error: e,
          );
          return ApiResponse.error('Unexpected response format');
        }
      }

      if (response.statusCode == 401) {
        return ApiResponse.error('Unauthorized - please login again');
      }

      if (response.statusCode == 404) {
        return ApiResponse.error('Hub is not online');
      }

      return ApiResponse.error(
        _apiMessage(
          response,
          fallback: 'Failed to reach the gateway: ${response.statusCode}',
        ),
      );
    } on DioException catch (e) {
      Logger.error('LCG DioException', tag: _tag, error: e);
      return ApiResponse.error(_handleDioError(e));
    } catch (e, stackTrace) {
      Logger.error('LCG error', tag: _tag, error: e, stackTrace: stackTrace);
      return ApiResponse.error('An unexpected error occurred');
    }
  }

  /// `POST /2/account/login`. On success the server sets the session cookie.
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

      // The endpoint has been retired, so the app is out of date.
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

  /// `POST /1/account/logout`.
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
        _apiMessage(
          response,
          fallback: 'Logout failed: ${response.statusCode}',
        ),
      );
    } on DioException catch (e) {
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

  /// v2 endpoints return the object directly; v1 wraps it in {message, data}.
  Map<String, dynamic>? _extractObject(dynamic responseData) {
    if (responseData is! Map<String, dynamic>) return null;

    final data = responseData['data'];
    if (data is Map<String, dynamic>) return data;

    return responseData;
  }

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

  /// Reads the API's RFC 7807 error text. `statusMessage` is usually empty
  /// over HTTP/2, and a Cloudflare block returns HTML rather than JSON.
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

  /// Error discriminator, e.g. `Turnstile.Invalid`. Both captcha failures and
  /// ordinary rejections are 403, so the type is what separates them.
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
