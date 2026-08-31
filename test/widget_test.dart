import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/main.dart';
import 'package:openshock_mobile/widgets/loading_state.dart';

import 'test_helpers.dart';

/// Runs the splash screen's post-frame init and its 500ms transition, so no
/// timer outlives the test.
Future<void> _settleSplash(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pump();
}

void main() {
  setUpFakeStorage();

  testWidgets('App boots into the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenShockApp());

    expect(find.byType(LoadingState), findsOneWidget);
    expect(find.text('Loading...'), findsOneWidget);

    await _settleSplash(tester);
  });

  testWidgets('App uses the dark theme', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenShockApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.dark);
    expect(app.debugShowCheckedModeBanner, isFalse);

    await _settleSplash(tester);
  });
}
