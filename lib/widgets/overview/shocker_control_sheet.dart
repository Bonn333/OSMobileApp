import 'dart:async';

import 'package:flutter/material.dart';
import '../../models/control_type.dart';
import '../../models/shared_shocker.dart';
import '../../models/device_with_shockers.dart';
import '../../services/live_control_client.dart';
import '../../services/ws_client.dart';
import '../../utils/logger.dart';
import 'live_control_pad.dart';

class ShockerControlSheet extends StatefulWidget {
  final dynamic shocker;
  final DeviceWithShockers? device;
  final OpenShockClient wsClient;

  const ShockerControlSheet({
    super.key,
    required this.shocker,
    required this.device,
    required this.wsClient,
  });

  @override
  State<ShockerControlSheet> createState() => _ShockerControlSheetState();
}

class _ShockerControlSheetState extends State<ShockerControlSheet> {
  double _intensity = 50;
  double _duration = 1000; // milliseconds
  bool _isSending = false;

  LiveControlClient? _live;
  LiveConnectionState _liveState = LiveConnectionState.disconnected;
  int _liveLatency = 0;
  ControlType _liveAction = ControlType.vibrate;
  final List<StreamSubscription<dynamic>> _liveSubscriptions = [];

  bool get _isLive => _liveState == LiveConnectionState.connected;

  String? get _hubId => widget.device?.id;

  @override
  void dispose() {
    for (final subscription in _liveSubscriptions) {
      subscription.cancel();
    }
    _live?.dispose();
    super.dispose();
  }

  Future<void> _toggleLive() async {
    if (_live != null) {
      await _stopLive();
      return;
    }

    final hubId = _hubId;
    if (hubId == null) {
      _showMessage('This shocker has no hub to control live', isError: true);
      return;
    }

    final client = LiveControlClient(hubId: hubId);
    _live = client;

    _liveSubscriptions.addAll([
      client.states.listen((state) {
        if (!mounted) return;
        setState(() => _liveState = state);
      }),
      client.latency.listen((value) {
        if (!mounted) return;
        setState(() => _liveLatency = value);
      }),
      client.errors.listen((message) {
        if (!mounted) return;
        _showMessage(message, isError: true);
      }),
    ]);

    await client.connect();
  }

  Future<void> _stopLive() async {
    final client = _live;
    _live = null;
    for (final subscription in _liveSubscriptions) {
      await subscription.cancel();
    }
    _liveSubscriptions.clear();
    await client?.dispose();

    if (!mounted) return;
    setState(() {
      _liveState = LiveConnectionState.disconnected;
      _liveLatency = 0;
    });
  }

  void _onLiveIntensity(int intensity) {
    if (!_isLive) return;
    _live?.hold(widget.shocker.id as String, _liveAction, intensity);
  }

  void _onLiveReleased() {
    _live?.release(widget.shocker.id as String);
  }

  Color _colorFor(ControlType action) => switch (action) {
    ControlType.shock => Colors.red,
    ControlType.vibrate => Colors.purple,
    ControlType.sound => Colors.orange,
    ControlType.stop => Colors.grey,
  };

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  int get maxIntensity {
    if (widget.shocker is SharedShocker) {
      return (widget.shocker as SharedShocker).limits.intensity ?? 100;
    }
    return 100; // Default max for own shockers
  }

  int get maxDuration {
    if (widget.shocker is SharedShocker) {
      return (widget.shocker as SharedShocker).limits.duration ?? 30000;
    }
    return 30000; // Default max 30 seconds for own shockers
  }

  bool get canControl {
    // Can't control if device is offline
    if (widget.device != null && !widget.device!.isOnline) {
      return false;
    }

    // Check permissions for shared shockers
    if (widget.shocker is SharedShocker) {
      final permissions = (widget.shocker as SharedShocker).permissions;
      return permissions.shock || permissions.vibrate || permissions.sound;
    }

    // Own shockers can always be controlled (if online)
    return true;
  }

  bool canUseAction(ControlType action) {
    if (widget.shocker is SharedShocker) {
      final permissions = (widget.shocker as SharedShocker).permissions;
      switch (action) {
        case ControlType.shock:
          return permissions.shock;
        case ControlType.vibrate:
          return permissions.vibrate;
        case ControlType.sound:
          return permissions.sound;
        case ControlType.stop:
          return true;
      }
    }
    return true; // Own shockers can use all actions
  }

  Future<void> _sendControl(ControlType action, String actionName) async {
    if (!canControl || !canUseAction(action)) return;

    setState(() => _isSending = true);

    try {
      final success = await widget.wsClient.sendControlSignal(
        widget.shocker.id,
        _intensity.toInt(),
        _duration.toInt(),
        action,
      );

      if (mounted) {
        if (success) {
          Logger.log(
            'Sent $actionName: intensity=${_intensity.toInt()}, duration=${_duration.toInt()}ms',
            tag: 'ShockerControl',
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$actionName sent: ${_intensity.toInt()}% for ${(_duration / 1000).toStringAsFixed(1)}s',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          Logger.error('Failed to send $actionName', tag: 'ShockerControl');

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to send $actionName'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      Logger.error(
        'Error sending $actionName',
        tag: 'ShockerControl',
        error: e,
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Widget _buildLiveActionSelector() {
    const actions = [
      (ControlType.sound, Icons.volume_up, 'Sound'),
      (ControlType.vibrate, Icons.waves, 'Vibrate'),
      (ControlType.shock, Icons.bolt, 'Shock'),
    ];

    return Row(
      children: [
        for (final (action, icon, label) in actions) ...[
          Expanded(
            child: _LiveActionTab(
              icon: icon,
              label: label,
              color: _colorFor(action),
              selected: _liveAction == action,
              enabled: canUseAction(action),
              onTap: () => setState(() => _liveAction = action),
            ),
          ),
          if (action != ControlType.shock) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildLiveBar(bool canControl) {
    final connecting = _liveState == LiveConnectionState.connecting;

    final Color accent = _isLive ? Colors.green : Colors.white70;
    final String status = switch (_liveState) {
      LiveConnectionState.connected => 'Live - hold a button to control',
      LiveConnectionState.connecting => 'Connecting to gateway...',
      LiveConnectionState.disconnected => 'Live control is off',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            _isLive ? Icons.bolt : Icons.bolt_outlined,
            color: accent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: TextStyle(color: accent, fontSize: 12)),
                if (_isLive && _liveLatency > 0)
                  Text(
                    '${_liveLatency}ms',
                    style: TextStyle(
                      color: Colors.green.shade200,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (connecting)
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: _isLive,
              onChanged: canControl ? (_) => _toggleLive() : null,
              activeThumbColor: Colors.green,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shockerName = widget.shocker.name as String;
    final isOnline = widget.device?.isOnline ?? false;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shockerName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            isOnline ? Icons.circle : Icons.circle,
                            size: 8,
                            color: isOnline ? Colors.green : Colors.red,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isOnline ? 'Online' : 'Offline',
                            style: TextStyle(
                              color: isOnline ? Colors.green : Colors.red,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white10, height: 1),

          // Controls
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Intensity slider
                const Text(
                  'Intensity',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: Colors.red,
                          inactiveTrackColor: Colors.red.withValues(alpha: 0.3),
                          thumbColor: Colors.red,
                          overlayColor: Colors.red.withValues(alpha: 0.2),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: _intensity,
                          min: 0,
                          max: maxIntensity.toDouble(),
                          divisions: maxIntensity,
                          onChanged: canControl
                              ? (value) => setState(() => _intensity = value)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 60,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_intensity.toInt()}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Duration slider
                const Text(
                  'Duration',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: Colors.blue,
                          inactiveTrackColor: Colors.blue.withValues(
                            alpha: 0.3,
                          ),
                          thumbColor: Colors.blue,
                          overlayColor: Colors.blue.withValues(alpha: 0.2),
                          trackHeight: 4,
                        ),
                        child: Slider(
                          value: _duration,
                          min: 300,
                          max: maxDuration.toDouble(),
                          divisions: ((maxDuration - 300) / 100).round(),
                          onChanged: canControl
                              ? (value) => setState(() => _duration = value)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 60,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${(_duration / 1000).toStringAsFixed(1)}s',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                _buildLiveBar(canControl),

                if (_isLive) ...[
                  const SizedBox(height: 12),
                  _buildLiveActionSelector(),
                  const SizedBox(height: 12),
                  LiveControlPad(
                    color: _colorFor(_liveAction),
                    maxIntensity: maxIntensity,
                    enabled: _isLive && canUseAction(_liveAction),
                    onChanged: _onLiveIntensity,
                    onReleased: _onLiveReleased,
                  ),
                ],

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: _ControlButton(
                        label: 'Shock',
                        icon: Icons.bolt,
                        color: Colors.red,
                        enabled: canControl && canUseAction(ControlType.shock),
                        isSending: _isSending,
                        onPressed: () =>
                            _sendControl(ControlType.shock, 'Shock'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ControlButton(
                        label: 'Vibrate',
                        icon: Icons.vibration,
                        color: Colors.purple,
                        enabled:
                            canControl && canUseAction(ControlType.vibrate),
                        isSending: _isSending,
                        onPressed: () =>
                            _sendControl(ControlType.vibrate, 'Vibrate'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ControlButton(
                        label: 'Sound',
                        icon: Icons.volume_up,
                        color: Colors.orange,
                        enabled: canControl && canUseAction(ControlType.sound),
                        isSending: _isSending,
                        onPressed: () =>
                            _sendControl(ControlType.sound, 'Sound'),
                      ),
                    ),
                  ],
                ),

                if (!canControl) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isOnline
                                ? 'You don\'t have permission to control this shocker'
                                : 'Device is offline',
                            style: TextStyle(color: Colors.red, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveActionTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _LiveActionTab({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = enabled && selected;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? color.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? color.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: enabled
                    ? (selected ? color : Colors.white54)
                    : Colors.grey,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: enabled
                      ? (selected ? color : Colors.white54)
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final bool isSending;
  final VoidCallback onPressed;

  const _ControlButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.isSending,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: enabled && !isSending ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled
            ? color.withValues(alpha: 0.2)
            : Colors.grey.withValues(alpha: 0.1),
        foregroundColor: enabled ? color : Colors.grey,
        disabledBackgroundColor: Colors.grey.withValues(alpha: 0.1),
        disabledForegroundColor: Colors.grey,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: enabled
                ? color.withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
