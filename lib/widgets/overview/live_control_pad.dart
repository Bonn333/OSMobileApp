import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Drag pad for live control.
///
/// Dragging sets intensity from 0 at the bottom to [maxIntensity] at the top,
/// and the trace scrolls right to left so a held value reads as a flat line.
/// Releasing drops to zero, which is what stops the shocker.
class LiveControlPad extends StatefulWidget {
  final Color color;
  final int maxIntensity;
  final bool enabled;
  final double height;

  /// Called continuously while dragging.
  final ValueChanged<int> onChanged;

  /// Called once the finger lifts.
  final VoidCallback onReleased;

  const LiveControlPad({
    super.key,
    required this.color,
    required this.onChanged,
    required this.onReleased,
    this.maxIntensity = 100,
    this.enabled = true,
    this.height = 180,
  });

  @override
  State<LiveControlPad> createState() => _LiveControlPadState();
}

class _LiveControlPadState extends State<LiveControlPad> {
  static const _sampleInterval = Duration(milliseconds: 40);
  static const _sampleCount = 90;

  final List<double> _trace = List<double>.filled(_sampleCount, 0);

  Timer? _sampler;
  double _intensity = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _sampler = Timer.periodic(_sampleInterval, (_) {
      if (!mounted) return;
      setState(() {
        _trace.removeAt(0);
        _trace.add(_intensity);
      });
    });
  }

  @override
  void dispose() {
    _sampler?.cancel();
    super.dispose();
  }

  void _updateFrom(Offset localPosition, Size size) {
    if (!widget.enabled) return;

    final fraction = 1 - (localPosition.dy / size.height);
    final value = (fraction.clamp(0.0, 1.0)) * widget.maxIntensity;

    setState(() => _intensity = value);
    widget.onChanged(value.round());
  }

  void _release() {
    if (!_isDragging) return;
    setState(() {
      _isDragging = false;
      _intensity = 0;
    });
    widget.onReleased();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled ? widget.color : Colors.grey;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);

        return RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: {
            _PadDragRecognizer:
                GestureRecognizerFactoryWithHandlers<_PadDragRecognizer>(
                  _PadDragRecognizer.new,
                  (recognizer) {
                    recognizer.onDown = (details) {
                      if (!widget.enabled) return;
                      setState(() => _isDragging = true);
                      _updateFrom(details.localPosition, size);
                    };
                    recognizer.onUpdate = (details) {
                      _updateFrom(details.localPosition, size);
                    };
                    recognizer.onEnd = (_) {
                      _release();
                    };
                    recognizer.onCancel = _release;
                  },
                ),
          },
          child: SizedBox(
            height: size.height,
            width: size.width,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: color.withValues(alpha: _isDragging ? 0.5 : 0.15),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TracePainter(
                      trace: _trace,
                      maxIntensity: widget.maxIntensity.toDouble(),
                      color: color,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  child: _IntensityPill(
                    value: _intensity.round(),
                    color: color,
                    active: _isDragging,
                  ),
                ),
                if (!widget.enabled)
                  Center(
                    child: Text(
                      'Turn on live control to use this',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                else if (!_isDragging)
                  Positioned(
                    top: 14,
                    child: Text(
                      'Drag up for more intensity',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Claims the pointer as soon as it goes down.
///
/// Without this the modal sheet's drag-to-dismiss and the surrounding scroll
/// view win the gesture arena, so dragging the pad closed the sheet or scrolled
/// the page instead of setting intensity.
class _PadDragRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _IntensityPill extends StatelessWidget {
  final int value;
  final Color color;
  final bool active;

  const _IntensityPill({
    required this.value,
    required this.color,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? color.withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? color.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Text(
        '$value%',
        style: TextStyle(
          color: active ? color : Colors.white54,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TracePainter extends CustomPainter {
  final List<double> trace;
  final double maxIntensity;
  final Color color;

  _TracePainter({
    required this.trace,
    required this.maxIntensity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trace.length < 2 || maxIntensity <= 0) return;

    // Inset the plot so a flat 0% line is drawn inside the box rather than
    // half-clipped against its bottom edge.
    const inset = 14.0;
    final plotHeight = size.height - inset * 2;
    final stepX = size.width / (trace.length - 1);

    double yFor(double value) =>
        inset + plotHeight - (value / maxIntensity) * plotHeight;

    final path = Path();

    for (var i = 0; i < trace.length; i++) {
      final x = i * stepX;
      final y = yFor(trace[i]);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        // Smooth the corners so a held value does not look like a staircase.
        final previousX = (i - 1) * stepX;
        final previousY = yFor(trace[i - 1]);
        final midX = (previousX + x) / 2;
        path.cubicTo(midX, previousY, midX, y, x, y);
      }
    }

    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // The trace list is mutated in place, so its identity never changes and a
  // reference comparison would never repaint.
  @override
  bool shouldRepaint(_TracePainter oldDelegate) => true;
}
