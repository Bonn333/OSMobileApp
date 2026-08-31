import 'package:dio/dio.dart';

import '../models/device_with_shockers.dart';
import '../models/self_user.dart';
import '../models/shared_user.dart';
import '../utils/logger.dart';

class ApiClient {
  static const String defaultBaseUrl = 'https://api.openshock.app';

  /// OpenShock requires every request to carry a meaningful User-Agent.
  /// Requests without one are rejected at the edge by Cloudflare with a 403
  /// and an HTML body, long before they reach the API.
  static const String userAgent = 'OpenShockMobile/1.0.0';

  static const _apiTokenHeader = 'OpenShockToken';
  static const _tag = 'ApiClient';

  late Dio _dio;

  String _baseUrl;
  bool _initialized = false;

  /// Held separately from the Dio instance because [setBaseUrl] rebuilds Dio,
  /// which would otherwise silently drop the auth header.
  String? _apiToken;

  /// Shared instance.
  ///
  /// The API token lives in memory on this object, so every caller has to talk
  /// to the same one. This used to not matter: authentication rode on cookies
  /// that each new instance reloaded from secure storage, so a second
  /// `ApiClient()` was still signed in. A second instance now would simply have
  /// no token and get 401 on everything.
  static final ApiClient _shared = ApiClient._internal();

  factory ApiClient() => _shared;

  ApiClient._internal() : _baseUrl = defaultBaseUrl;

  String get baseUrl => _baseUrl;

  Future<void> setBaseUrl(String baseUrl) async {
    _baseUrl = baseUrl;

    // If already initialized, we need to reinitialize Dio with the new base URL
    if (_initialized) {
      _initializeDio();
    } else {
      await _ensureInitialized();
    }
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    _initializeDio();
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

    // Re-attach the token, since this may be a rebuild after a host change.
    _applyApiToken();
  }

  // -------------------------
  // Authentication
  // -------------------------

  /// Attach (or clear) the API token sent on every request.
  ///
  /// The header name comes from the `ApiToken` security scheme in the OpenAPI
  /// document (`OpenShockToken`). Note the developer wiki spells it
  /// `Open-Shock-Token`, which the server does not recognise - the spec wins.
  Future<void> setApiToken(String? token) async {
    _apiToken = (token == null || token.isEmpty) ? null : token;
    await _ensureInitialized();
    _applyApiToken();

    Logger.log(
      _apiToken == null ? 'Cleared API token' : 'API token attached',
      tag: _tag,
    );
  }

  String? get apiToken => _apiToken;

  void _applyApiToken() {
    if (_apiToken == null) {
      _dio.options.headers.remove(_apiTokenHeader);
      return;
    }
    _dio.options.headers[_apiTokenHeader] = _apiToken;
  }

  // -------------------------
  // API calls
  // -------------------------

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
