import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/widgets/overview/arc_slider.dart';

void main() {
  late double value;

  Future<void> pumpSlider(
    WidgetTester tester, {
    double initial = 0,
    double min = 0,
    double max = 100,
    bool enabled = true,
  }) {
    value = initial;

    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) => ArcSlider(
                label: 'Intensity',
                value: value,
                min: min,
                max: max,
                color: Colors.red,
                enabled: enabled,
                display: (v) => '${v.round()}',
                editValue: (v) => '${v.round()}',
                parse: (text) => double.tryParse(text.replaceAll(',', '.')),
                onChanged: (v) => setState(() => value = v),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // The gauge starts south-west and sweeps 270 degrees clockwise, so straight
  // up is the middle of the range.
  testWidgets('dragging to the top sets the midpoint', (tester) async {
    await pumpSlider(tester);

    final rect = tester.getRect(find.byType(ArcSlider));
    // The arc is the square at the top of the column; the label sits below it.
    final arcCentre = Offset(rect.center.dx, rect.top + 66);

    final gesture = await tester.startGesture(arcCentre + const Offset(-40, 0));
    await tester.pump();
    await gesture.moveTo(arcCentre - const Offset(0, 40));
    await tester.pump();
    await gesture.up();

    expect(value, closeTo(50, 6));
  });

  testWidgets('tapping the value opens a keyboard editor', (tester) async {
    await pumpSlider(tester, initial: 25);

    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('25'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '80');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(value, 80);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('typed values are clamped to the range', (tester) async {
    await pumpSlider(tester, initial: 10, max: 30);

    await tester.tap(find.text('10'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(value, 30);
  });

  testWidgets('rubbish input leaves the value alone', (tester) async {
    await pumpSlider(tester, initial: 42);

    await tester.tap(find.text('42'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(value, 42);
  });

  testWidgets('disabled slider ignores drags and taps', (tester) async {
    await pumpSlider(tester, initial: 20, enabled: false);

    final rect = tester.getRect(find.byType(ArcSlider));
    final ring = Offset(rect.center.dx, rect.top + 12);
    await tester.dragFrom(ring, const Offset(20, 20));
    await tester.pump();

    await tester.tap(find.text('20'));
    await tester.pump();

    expect(value, 20);
    expect(find.byType(TextField), findsNothing);
  });
}
