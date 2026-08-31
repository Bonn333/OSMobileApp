import 'dart:async';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:signalr_core/signalr_core.dart';

import '../models/control_type.dart';
import '../utils/logger.dart';

/// Example event envelope for stream output
class OpenShockHubEvent {
  final String method;
  final List<Object?>? args;
  OpenShockHubEvent(this.method, this.args);

  @override
  String toString() => 'OpenShockHubEvent(method: $method, args: $args)';
}

class OpenShockClient {
  final String apiHost;

  /// Value of the `openShockSession` cookie. The hub is authenticated with the
  /// session rather than an API token, matching the cookie-based login flow.
  final String sessionKey;

  final Dio dio;
  HubConnection? _connection;

  // Stream-based outputs
  final _eventsCtrl = StreamController<OpenShockHubEvent>.broadcast();
  final _stateCtrl = StreamController<HubConnectionState>.broadcast();
  final _errorsCtrl = StreamController<Object>.broadcast();

  Stream<OpenShockHubEvent> get events => _eventsCtrl.stream;
  Stream<HubConnectionState> get states => _stateCtrl.stream;
  Stream<Object> get errors => _errorsCtrl.stream;

  /// Provide your own Dio if you want (custom timeouts, proxy, etc.)
  OpenShockClient({
    required this.apiHost,
    required this.sessionKey,
    Dio? dio,
    required String userAgent,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               // Make sure baseUrl doesn't double-slash with apiHost usage
               baseUrl: apiHost,
               headers: {
                 'OpenShockSession': sessionKey,
                 'User-Agent': userAgent,
               },
             ),
           ) {
    // Ensure headers always exist (even if caller provided Dio)
    this.dio.options.headers.addAll({
      'OpenShockSession': sessionKey,
      'User-Agent': userAgent,
    });
  }

  /// Start SignalR connection (WebSockets, skip negotiation like your original)
  Future<void> start() async {
    try {
      final httpClient = _OpenShockHttpClient(
        sessionKey: sessionKey,
        userAgent:
            dio.options.headers['User-Agent'] as String? ??
            'OpenShockMobile/1.0.0',
      );

      _connection = HubConnectionBuilder()
          .withAutomaticReconnect()
          .withUrl(
            '$apiHost/1/hubs/user',
            HttpConnectionOptions(
              client: httpClient,
              skipNegotiation: true,
              transport: HttpTransportType.webSockets,
              logMessageContent: true,
              logging: (level, message) {
                Logger.log('[$level]: $message', tag: 'SignalRWSClient');
              },
            ),
          )
          .build();

      // Track state changes by polling when something important happens
      void emitState() {
        final c = _connection;
        if (c != null && c.state != null) _stateCtrl.add(c.state!);
      }

      _connection!.onclose((error) {
        if (error != null) _errorsCtrl.add(error);
        emitState();
      });

      _connection!.onreconnecting((error) {
        if (error != null) _errorsCtrl.add(error);
        emitState();
      });

      _connection!.onreconnected((connectionId) {
        emitState();
      });

      await _connection!.start();
      emitState();
    } catch (e) {
      _errorsCtrl.add(e);
      rethrow;
    }
  }

  /// Stop and dispose
  Future<void> stop() async {
    final c = _connection;
    if (c == null) return;
    try {
      await c.stop();
      if (c.state != null) _stateCtrl.add(c.state!);
    } catch (e) {
      _errorsCtrl.add(e);
      rethrow;
    }
  }

  /// Clean up streams + connection
  Future<void> dispose() async {
    await stop();
    await _eventsCtrl.close();
    await _stateCtrl.close();
    await _errorsCtrl.close();
  }

  /// Stream-based subscription helper: listen to only one hub method.
  /// This does NOT create multiple hub handlers; it filters the single events stream.
  Stream<OpenShockHubEvent> onMethod(String methodName) =>
      events.where((e) => e.method == methodName);

  /// Registers a hub handler that forwards into the events stream.
  /// Call once per hub method you care about.
  void registerForwarder(String methodName) {
    final c = _connection;
    if (c == null) {
      throw StateError('Connection not started. Call start() first.');
    }

    c.on(methodName, (args) {
      _eventsCtrl.add(OpenShockHubEvent(methodName, args));
    });
  }

  /// Optional: remove handler for a method
  void unregister(String methodName) {
    final c = _connection;
    if (c == null) return;
    c.off(methodName);
  }

  /// Send a custom hub command
  Future<bool> sendCommand(String methodName, {List<Object?>? args}) async {
    final c = _connection;
    if (c == null) return false;

    try {
      await c.invoke(methodName, args: args ?? []);
      return true;
    } catch (e) {
      _errorsCtrl.add(e);
      return false;
    }
  }

  /// Your original sendControlSignal, unchanged behavior.
  /// (Still sends over the hub with methodName 'ControlV2'.)
  Future<bool> sendControlSignal(
    String id,
    int intensity,
    int duration,
    ControlType action,
  ) async {
    final c = _connection;
    if (c == null) return false;

    final data = <String, dynamic>{
      'Id': id,
      // Must be the API's ControlType value, not a zero-based index.
      'Type': action.value,
      'Duration': duration,
      'Intensity': intensity,
    };

    try {
      // same payload shape you had: args: [ [data], null ]
      await c.send(
        methodName: 'ControlV2',
        args: [
          [data],
          null,
        ],
      );
      return true;
    } catch (e) {
      _errorsCtrl.add(e);
      return false;
    }
  }
}

/// Custom HTTP client that adds OpenShock headers to all requests
class _OpenShockHttpClient extends http.BaseClient {
  final http.Client _httpClient = http.Client();
  final String sessionKey;
  final String userAgent;

  _OpenShockHttpClient({required this.sessionKey, required this.userAgent});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll({
      'OpenShockSession': sessionKey,
      'User-Agent': userAgent,
    });
    return _httpClient.send(request);
  }
}
