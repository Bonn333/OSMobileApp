import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/main.dart';
import 'package:openshock_mobile/widgets/loading_state.dart';

void main() {
  testWidgets('App boots into the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenShockApp());

    // The splash screen shows the spinner with a status message. Note it does
    // not render the word "OpenShock" anywhere, which is what the original
    // generated test asserted.
    expect(find.byType(LoadingState), findsOneWidget);
    expect(find.text('Loading...'), findsOneWidget);
  });

  testWidgets('App uses the dark theme', (WidgetTester tester) async {
    await tester.pumpWidget(const OpenShockApp());

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme?.brightness, Brightness.dark);
    expect(app.debugShowCheckedModeBanner, isFalse);
  });
}
