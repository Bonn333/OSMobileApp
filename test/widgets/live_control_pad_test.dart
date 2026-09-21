import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/widgets/overview/live_control_pad.dart';

void main() {
  Future<void> pumpPad(
    WidgetTester tester, {
    required List<int> reported,
    required List<int> releases,
    int maxIntensity = 100,
    bool enabled = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: LiveControlPad(
                color: Colors.purple,
                maxIntensity: maxIntensity,
                enabled: enabled,
                height: 200,
                onChanged: reported.add,
                onReleased: () => releases.add(1),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('reports intensity while dragging and zero on release', (
    tester,
  ) async {
    final reported = <int>[];
    final releases = <int>[];
    await pumpPad(tester, reported: reported, releases: releases);

    final pad = tester.getRect(find.byType(LiveControlPad));
    final gesture = await tester.startGesture(
      pad.bottomCenter - const Offset(0, 4),
    );
    await tester.pump();

    expect(reported.first, lessThan(10));

    await gesture.moveTo(pad.center);
    await tester.pump();
    await gesture.moveTo(pad.topCenter + const Offset(0, 4));
    await tester.pump();

    expect(reported.last, greaterThan(90));

    await gesture.up();
    await tester.pump();

    expect(releases, hasLength(1));
  });

  testWidgets('caps intensity at the shocker limit', (tester) async {
    final reported = <int>[];
    final releases = <int>[];
    await pumpPad(
      tester,
      reported: reported,
      releases: releases,
      maxIntensity: 30,
    );

    final pad = tester.getRect(find.byType(LiveControlPad));
    final gesture = await tester.startGesture(
      pad.topCenter + const Offset(0, 2),
    );
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(reported.every((value) => value <= 30), isTrue);
    expect(reported.first, greaterThan(25));
  });

  testWidgets('ignores drags when disabled', (tester) async {
    final reported = <int>[];
    final releases = <int>[];
    await pumpPad(
      tester,
      reported: reported,
      releases: releases,
      enabled: false,
    );

    final pad = tester.getRect(find.byType(LiveControlPad));
    final gesture = await tester.startGesture(pad.center);
    await tester.pump();
    await gesture.moveTo(pad.topCenter);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(reported, isEmpty);
    expect(releases, isEmpty);
  });
}
