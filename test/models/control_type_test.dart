import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/control_type.dart';

void main() {
  group('ControlType', () {
    test('matches the API ControlType values', () {
      expect(ControlType.stop.value, 0);
      expect(ControlType.shock.value, 1);
      expect(ControlType.vibrate.value, 2);
      expect(ControlType.sound.value, 3);
    });
  });
}
