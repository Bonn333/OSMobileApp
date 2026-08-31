import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/secure_storage_data.dart';

void main() {
  group('SecureStorageData', () {
    test('round-trips through JSON', () {
      const data = SecureStorageData(
        apiToken: 'token-abc',
        sessionCookies: 'cookie-jar',
      );

      final restored = SecureStorageData.fromJsonString(data.toJsonString());

      expect(restored.apiToken, 'token-abc');
      expect(restored.sessionCookies, 'cookie-jar');
    });

    test('empty() carries no secrets', () {
      final data = SecureStorageData.empty();

      expect(data.apiToken, isNull);
      expect(data.sessionCookies, isNull);
    });

    test('copyWith leaves omitted fields untouched', () {
      const data = SecureStorageData(
        apiToken: 'token-abc',
        sessionCookies: 'cookie-jar',
      );

      final updated = data.copyWith(apiToken: 'token-xyz');

      expect(updated.apiToken, 'token-xyz');
      expect(updated.sessionCookies, 'cookie-jar');
    });
    
    test('copyWith clears the token when asked, not when passed null', () {
      const data = SecureStorageData(
        apiToken: 'token-abc',
        sessionCookies: 'cookie-jar',
      );

      expect(data.copyWith(apiToken: null).apiToken, 'token-abc');
      expect(data.copyWith(clearApiToken: true).apiToken, isNull);
    });

    test('clearing one secret leaves the other alone', () {
      const data = SecureStorageData(
        apiToken: 'token-abc',
        sessionCookies: 'cookie-jar',
      );

      final cleared = data.copyWith(clearApiToken: true);

      expect(cleared.apiToken, isNull);
      expect(cleared.sessionCookies, 'cookie-jar');
    });

    test('clearing both secrets empties the record', () {
      const data = SecureStorageData(
        apiToken: 'token-abc',
        sessionCookies: 'cookie-jar',
      );

      final cleared = data.copyWith(
        clearApiToken: true,
        clearSessionCookies: true,
      );

      expect(cleared.apiToken, isNull);
      expect(cleared.sessionCookies, isNull);
    });
  });
}
