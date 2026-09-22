import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../eager_pan_recognizer.dart';

/// Gauge-style value control: drag around the arc, or tap the value to type it.
class ArcSlider extends StatefulWidget {
  final double value;
  final double min;
  final double max;
  final String label;
  final Color color;
  final bool enabled;
  final double size;

  /// Text shown in the middle of the arc.
  final String Function(double value) display;

  /// Prefilled when the editor opens, in the same units as [parse] returns.
  final String Function(double value) editValue;

  /// Null rejects the input and keeps the previous value.
  final double? Function(String text) parse;

  final ValueChanged<double> onChanged;

  const ArcSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.label,
    required this.color,
    required this.display,
    required this.editValue,
    required this.parse,
    required this.onChanged,
    this.enabled = true,
    this.size = 132,
  });

  @override
  State<ArcSlider> createState() => _ArcSliderState();
}

class _ArcSliderState extends State<ArcSlider> {
  // Gauge open at the bottom: starts south-west, sweeps clockwise past north.
  static const double _startAngle = 3 * math.pi / 4;
  static const double _sweepAngle = 3 * math.pi / 2;
  static const double _strokeWidth = 14;
  static const double _knobRadius = 13;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _editing) _commit();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  double get _fraction {
    final span = widget.max - widget.min;
    if (span <= 0) return 0;
    return ((widget.value - widget.min) / span).clamp(0.0, 1.0);
  }

  void _startEditing() {
    if (!widget.enabled) return;
    _controller.text = widget.editValue(widget.value);
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
    setState(() => _editing = true);
  }

  void _commit() {
    final parsed = widget.parse(_controller.text);
    setState(() => _editing = false);

    if (parsed == null) return;
    widget.onChanged(parsed.clamp(widget.min, widget.max));
  }

  void _updateFromPosition(Offset local) {
    if (!widget.enabled) return;

    final center = Offset(widget.size / 2, widget.size / 2);
    final vector = local - center;
    if (vector.distance < _strokeWidth) return;

    var angle = math.atan2(vector.dy, vector.dx);
    if (angle < 0) angle += 2 * math.pi;

    var delta = angle - _startAngle;
    if (delta < 0) delta += 2 * math.pi;

    double fraction;
    if (delta > _sweepAngle) {
      // In the gap at the bottom, snap to whichever end is nearer.
      final toEnd = delta - _sweepAngle;
      final toStart = 2 * math.pi - delta;
      fraction = toEnd < toStart ? 1 : 0;
    } else {
      fraction = delta / _sweepAngle;
    }

    widget.onChanged(widget.min + fraction * (widget.max - widget.min));
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled ? widget.color : Colors.grey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          // The value sits beside the gesture layer rather than inside it: the
          // eager recognizer claims the pointer on down, so a tap nested under
          // it would never fire.
          child: Stack(
            children: [
              Positioned.fill(
                child: RawGestureDetector(
                  behavior: HitTestBehavior.opaque,
                  gestures: {
                    EagerPanRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          EagerPanRecognizer
                        >(EagerPanRecognizer.new, (recognizer) {
                          recognizer.onDown = (details) =>
                              _updateFromPosition(details.localPosition);
                          recognizer.onUpdate = (details) =>
                              _updateFromPosition(details.localPosition);
                        }),
                  },
                  child: CustomPaint(
                    painter: _ArcPainter(
                      fraction: _fraction,
                      color: color,
                      startAngle: _startAngle,
                      sweepAngle: _sweepAngle,
                      strokeWidth: _strokeWidth,
                      knobRadius: _knobRadius,
                    ),
                  ),
                ),
              ),
              Center(
                child: SizedBox(
                  width: widget.size * 0.56,
                  child: _editing ? _buildEditor(color) : _buildValue(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.label,
          style: TextStyle(
            color: widget.enabled ? Colors.white70 : Colors.grey,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildValue() {
    return GestureDetector(
      onTap: _startEditing,
      behavior: HitTestBehavior.opaque,
      child: FittedBox(
        child: Text(
          widget.display(widget.value),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: widget.enabled ? Colors.white : Colors.grey,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEditor(Color color) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      autofocus: true,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      style: const TextStyle(
        color: Colors.white,
        fontSize: 22,
        fontWeight: FontWeight.bold,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 4),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: color),
        ),
      ),
      onSubmitted: (_) => _commit(),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final double startAngle;
  final double sweepAngle;
  final double strokeWidth;
  final double knobRadius;

  _ArcPainter({
    required this.fraction,
    required this.color,
    required this.startAngle,
    required this.sweepAngle,
    required this.strokeWidth,
    required this.knobRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - knobRadius;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawArc(
      rect,
      startAngle,
      sweepAngle,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    if (fraction > 0) {
      canvas.drawArc(
        rect,
        startAngle,
        sweepAngle * fraction,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round,
      );
    }

    final knobAngle = startAngle + sweepAngle * fraction;
    final knob =
        center + Offset(math.cos(knobAngle), math.sin(knobAngle)) * radius;

    canvas.drawCircle(
      knob,
      knobRadius,
      Paint()..color = const Color(0xFF2A2A2A),
    );
    canvas.drawCircle(
      knob,
      knobRadius,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_ArcPainter oldDelegate) =>
      oldDelegate.fraction != fraction || oldDelegate.color != color;
}
