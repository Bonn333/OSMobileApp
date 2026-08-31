import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/control_type.dart';

void main() {
  group('ControlType', () {
    // These values are the wire format for the hub's ControlV2 `Type` field and
    // must match the API's ControlType enum. Getting them wrong does not fail
    // loudly - it silently fires the wrong action on real hardware, so pin them
    // explicitly rather than trusting declaration order.
    test('matches the API ControlType values', () {
      expect(ControlType.stop.value, 0);
      expect(ControlType.shock.value, 1);
      expect(ControlType.vibrate.value, 2);
      expect(ControlType.sound.value, 3);
    });

    // Regression test: the actions used to be zero-based constants
    // (shock = 0, vibrate = 1, sound = 2), which shifted everything down one
    // so Sound vibrated, Vibrate shocked, and Shock sent Stop.
    test('is not numbered from zero by action', () {
      expect(ControlType.shock.value, isNot(0));
      expect(ControlType.vibrate.value, isNot(1));
      expect(ControlType.sound.value, isNot(2));
    });

    test('no two actions share a value', () {
      final values = ControlType.values.map((t) => t.value).toList();
      expect(values.toSet().length, values.length);
    });

    test('sound is the strongest-numbered and stop the weakest', () {
      expect(ControlType.stop.value, lessThan(ControlType.shock.value));
      expect(ControlType.shock.value, lessThan(ControlType.vibrate.value));
      expect(ControlType.vibrate.value, lessThan(ControlType.sound.value));
    });
  });
}
