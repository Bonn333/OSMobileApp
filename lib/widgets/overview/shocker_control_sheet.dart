import 'package:flutter/material.dart';
import '../../models/control_type.dart';
import '../../models/shared_shocker.dart';
import '../../models/device_with_shockers.dart';
import '../../services/ws_client.dart';
import '../../utils/logger.dart';

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
      Logger.error('Error sending $actionName', tag: 'ShockerControl', error: e);
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
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
                          inactiveTrackColor: Colors.blue.withValues(alpha: 0.3),
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

                const SizedBox(height: 32),

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
                        onPressed: () => _sendControl(ControlType.shock, 'Shock'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _ControlButton(
                        label: 'Vibrate',
                        icon: Icons.vibration,
                        color: Colors.purple,
                        enabled: canControl && canUseAction(ControlType.vibrate),
                        isSending: _isSending,
                        onPressed: () => _sendControl(ControlType.vibrate, 'Vibrate'),
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
                        onPressed: () => _sendControl(ControlType.sound, 'Sound'),
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
        backgroundColor: enabled ? color.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.1),
        foregroundColor: enabled ? color : Colors.grey,
        disabledBackgroundColor: Colors.grey.withValues(alpha: 0.1),
        disabledForegroundColor: Colors.grey,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: enabled ? color.withValues(alpha: 0.5) : Colors.grey.withValues(alpha: 0.3),
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
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
