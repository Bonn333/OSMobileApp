import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/login_request.dart';

void main() {
  group('LoginRequest', () {
    test('serialises the field names /2/account/login expects', () {
      final json = LoginRequest(
        usernameOrEmail: 'someone@example.com',
        password: 'hunter2',
        turnstileResponse: 'turnstile-token',
      ).toJson();

      expect(json.keys.toSet(), {
        'usernameOrEmail',
        'password',
        'turnstileResponse',
      });
      expect(json['usernameOrEmail'], 'someone@example.com');
      expect(json['password'], 'hunter2');
      expect(json['turnstileResponse'], 'turnstile-token');
    });
  });
}
