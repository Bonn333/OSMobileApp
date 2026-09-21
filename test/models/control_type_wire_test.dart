import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/control_type.dart';

void main() {
  group('ControlType wire names', () {
    test('serialise as the gateway expects', () {
      expect(ControlType.stop.name, 'stop');
      expect(ControlType.shock.name, 'shock');
      expect(ControlType.vibrate.name, 'vibrate');
      expect(ControlType.sound.name, 'sound');
    });
  });
}
