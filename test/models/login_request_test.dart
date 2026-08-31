import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/login_request.dart';

void main() {
  group('LoginRequest', () {
    // These field names are the v2 contract. v1 used `email` and was retired
    // (410 Gone); sending the old name to v2 fails validation with 400.
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

    test('does not send the retired v1 email field', () {
      final json = LoginRequest(
        usernameOrEmail: 'someone@example.com',
        password: 'hunter2',
        turnstileResponse: 'turnstile-token',
      ).toJson();

      expect(json.containsKey('email'), isFalse);
    });

    // The server rejects a missing, null or empty turnstileResponse with 400,
    // so the field always has to be present in the payload.
    test('always includes turnstileResponse', () {
      final json = LoginRequest(
        usernameOrEmail: 'user',
        password: 'pw',
        turnstileResponse: 'x',
      ).toJson();

      expect(json.containsKey('turnstileResponse'), isTrue);
    });
  });
}
