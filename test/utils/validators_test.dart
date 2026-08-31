import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/utils/validators.dart';

void main() {
  group('validateUsernameOrEmail', () {
    test('rejects an empty identifier', () {
      expect(validateUsernameOrEmail(''), isNotNull);
      expect(validateUsernameOrEmail('   '), isNotNull);
      expect(validateUsernameOrEmail(null), isNotNull);
    });

    test('accepts a valid email', () {
      expect(validateUsernameOrEmail('someone@example.com'), isNull);
    });

    // Anything with an @ can only be an email: the server refuses usernames
    // that contain one.
    test('rejects a malformed email', () {
      expect(validateUsernameOrEmail('someone@'), isNotNull);
      expect(validateUsernameOrEmail('@example.com'), isNotNull);
      expect(validateUsernameOrEmail('someone@example'), isNotNull);
      expect(validateUsernameOrEmail('a b@example.com'), isNotNull);
    });

    test('accepts a valid username', () {
      expect(validateUsernameOrEmail('sticks'), isNull);
      expect(validateUsernameOrEmail('user.name_1-2'), isNull);
    });

    test('enforces the server length limits', () {
      expect(validateUsernameOrEmail('ab'), isNotNull);
      expect(validateUsernameOrEmail('a' * usernameMinLength), isNull);
      expect(validateUsernameOrEmail('a' * usernameMaxLength), isNull);
      expect(validateUsernameOrEmail('a' * (usernameMaxLength + 1)), isNotNull);
    });

    test('rejects invisible and control characters', () {
      expect(validateUsernameOrEmail('user\u200Bname'), isNotNull);
      expect(validateUsernameOrEmail('user\u0007name'), isNotNull);
    });

    // The server only forbids leading and trailing whitespace, so a name with
    // an inner space stays valid once trimmed.
    test('trims surrounding whitespace', () {
      expect(validateUsernameOrEmail('  sticks  '), isNull);
      expect(validateUsernameOrEmail('some one'), isNull);
    });
  });

  group('validatePassword', () {
    test('only requires a non-empty value', () {
      expect(validatePassword(''), isNotNull);
      expect(validatePassword(null), isNotNull);
      expect(validatePassword('x'), isNull);
    });
  });
}
