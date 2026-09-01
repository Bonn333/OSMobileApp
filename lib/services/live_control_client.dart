import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/control_type.dart';
import '../utils/logger.dart';
import 'api_client.dart';

enum LiveConnectionState { disconnected, connecting, connected }

/// Live control over the gateway websocket, matching the web frontend.
///
/// The API only routes here: `GET /2/devices/{id}/lcg` says which gateway to
/// use, and the socket at `<prefix>/1/ws/live/{hubId}` takes control frames.
/// Frames are resent on a tick while the user holds a control, and the hub
/// stops on its own once they stop arriving.
class LiveControlClient {
  static const _tag = 'LiveControl';
  static const Duration defaultTickInterval = Duration(milliseconds: 100);

  final String hubId;
  final ApiClient _apiClient;

  LiveControlClient({required this.hubId, ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _tickTimer;

  final _stateController = StreamController<LiveConnectionState>.broadcast();
  final _latencyController = StreamController<int>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  /// Latest frame per shocker, resent every tick until cleared.
  final Map<String, _LiveFrame> _activeFrames = {};

  LiveConnectionState _state = LiveConnectionState.disconnected;
  Duration _tickInterval = defaultTickInterval;
  int _connectAttempt = 0;

  Stream<LiveConnectionState> get states => _stateController.stream;
  Stream<int> get latency => _latencyController.stream;
  Stream<String> get errors => _errorController.stream;

  LiveConnectionState get state => _state;
  bool get isConnected => _state == LiveConnectionState.connected;

  Future<void> connect() async {
    await disconnect();

    final attempt = ++_connectAttempt;
    _setState(LiveConnectionState.connecting);

    final gateway = await _apiClient.getLiveControlGateway(hubId);
    if (attempt != _connectAttempt) return;

    if (!gateway.isSuccess || gateway.data == null) {
      _fail(gateway.error ?? 'Could not reach the live control gateway');
      return;
    }

    final sessionKey = await _apiClient.getSessionKey();
    if (attempt != _connectAttempt) return;

    if (sessionKey == null) {
      _fail('Not signed in');
      return;
    }

    final uri = gateway.data!.liveSocketUri(hubId);
    Logger.log('Connecting to $uri', tag: _tag);

    try {
      // The gateway accepts the session as a header as well as a cookie, which
      // is what lets a native client authenticate the socket.
      final channel = IOWebSocketChannel.connect(
        uri,
        headers: {
          'OpenShockSession': sessionKey,
          'User-Agent': ApiClient.userAgent,
        },
      );
      _channel = channel;

      await channel.ready;
      if (attempt != _connectAttempt) {
        await channel.sink.close();
        return;
      }

      _subscription = channel.stream.listen(
        _onMessage,
        onError: (Object error) => _fail('Live control error: $error'),
        onDone: () {
          if (attempt != _connectAttempt) return;
          Logger.log('Gateway closed the connection', tag: _tag);
          _teardown();
          _setState(LiveConnectionState.disconnected);
        },
      );

      _setState(LiveConnectionState.connected);
      _startTicking();
    } catch (e, stackTrace) {
      Logger.error(
        'Failed to open live control socket',
        tag: _tag,
        error: e,
        stackTrace: stackTrace,
      );
      _fail('Could not connect to the live control gateway');
    }
  }

  Future<void> disconnect() async {
    _connectAttempt++;
    _teardown();
    if (_state != LiveConnectionState.disconnected) {
      _setState(LiveConnectionState.disconnected);
    }
  }

  /// Holds [shockerId] at [intensity] until [release] is called.
  void hold(String shockerId, ControlType type, int intensity) {
    _activeFrames[shockerId] = _LiveFrame(type, intensity.clamp(0, 100));
    _sendFrame(shockerId, _activeFrames[shockerId]!);
  }

  /// Stops [shockerId]. Sends a zero-intensity frame so the hub stops at once
  /// rather than waiting for the frames to time out.
  void release(String shockerId) {
    final frame = _activeFrames.remove(shockerId);
    if (frame == null) return;
    _sendFrame(shockerId, _LiveFrame(frame.type, 0));
  }

  void releaseAll() {
    for (final shockerId in _activeFrames.keys.toList()) {
      release(shockerId);
    }
  }

  void _startTicking() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(_tickInterval, (_) {
      if (!isConnected) return;
      _activeFrames.forEach(_sendFrame);
    });
  }

  void _sendFrame(String shockerId, _LiveFrame frame) {
    if (!isConnected) return;

    _send({
      'RequestType': 'Frame',
      'Data': {
        'Shocker': shockerId,
        'Intensity': frame.intensity,
        'Type': frame.type.name,
      },
    });
  }

  void _send(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (e) {
      Logger.error('Failed to send frame', tag: _tag, error: e);
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;

    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      message = decoded;
    } catch (_) {
      return;
    }

    final data = message['Data'];
    switch (message['ResponseType'] as String?) {
      case 'Ping':
        _send({
          'RequestType': 'Pong',
          'Data': {'Timestamp': data is Map ? data['Timestamp'] : null},
        });
        break;
      case 'LatencyAnnounce':
        if (data is Map && data['OwnLatency'] is num) {
          _latencyController.add((data['OwnLatency'] as num).round());
        }
        break;
      case 'TPS':
        // The gateway dictates how often it wants frames.
        final tps = (data is Map ? data['Client'] : null) as num?;
        if (tps != null && tps > 0) {
          _tickInterval = Duration(milliseconds: (1000 / tps).round());
          if (isConnected) _startTicking();
        }
        break;
      case 'DeviceNotConnected':
        _errorController.add('Hub is offline');
        break;
      case 'ShockerNotFound':
        _errorController.add('Shocker not found');
        break;
      case 'ShockerMissingLivePermission':
        _errorController.add('You do not have live control permission');
        break;
      case 'ShockerMissingPermission':
        _errorController.add('You do not have permission for that action');
        break;
      case 'ShockerPaused':
        _errorController.add('Shocker is paused');
        break;
      case 'ShockerExclusive':
        _errorController.add('Someone else is controlling this shocker');
        break;
      case 'TokenPaused':
        _errorController.add('This API token is paused');
        break;
      case 'InvalidData':
      case 'RequestTypeNotFound':
        _errorController.add('The gateway rejected the request');
        break;
    }
  }

  void _fail(String message) {
    Logger.error(message, tag: _tag);
    _errorController.add(message);
    _teardown();
    _setState(LiveConnectionState.disconnected);
  }

  void _teardown() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _activeFrames.clear();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _setState(LiveConnectionState state) {
    _state = state;
    if (!_stateController.isClosed) _stateController.add(state);
  }

  Future<void> dispose() async {
    await disconnect();
    await _stateController.close();
    await _latencyController.close();
    await _errorController.close();
  }
}

class _LiveFrame {
  final ControlType type;
  final int intensity;

  const _LiveFrame(this.type, this.intensity);
}
