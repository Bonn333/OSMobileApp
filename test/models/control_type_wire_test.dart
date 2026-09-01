import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/control_type.dart';

void main() {
  // Live control frames send the control type by name, not by number, and the
  // gateway matches the names the web frontend sends.
  group('ControlType wire names', () {
    test('serialise as the gateway expects', () {
      expect(ControlType.stop.name, 'stop');
      expect(ControlType.shock.name, 'shock');
      expect(ControlType.vibrate.name, 'vibrate');
      expect(ControlType.sound.name, 'sound');
    });
  });
}
