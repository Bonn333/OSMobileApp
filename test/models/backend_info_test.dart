import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/backend_info.dart';

void main() {
  group('BackendInfo Turnstile configuration', () {
    test('enables Turnstile when a site key is present', () {
      final info = BackendInfo.fromJson({
        'version': '3.17.0',
        'turnstileSiteKey': 'site-key',
      });

      expect(info.turnstileSiteKey, 'site-key');
      expect(info.isTurnstileEnabled, isTrue);
    });

    for (final siteKey in [null, '']) {
      test('disables Turnstile when the site key is ${siteKey ?? 'null'}', () {
        final info = BackendInfo.fromJson({
          'version': '3.17.0',
          'turnstileSiteKey': siteKey,
        });

        expect(info.turnstileSiteKey, isNull);
        expect(info.isTurnstileEnabled, isFalse);
      });
    }

    test('disables Turnstile when the site key is absent', () {
      final info = BackendInfo.fromJson({'version': '3.17.0'});

      expect(info.turnstileSiteKey, isNull);
      expect(info.isTurnstileEnabled, isFalse);
    });
  });

  group('BackendInfo OAuth providers', () {
    test('reads the provider list', () {
      final info = BackendInfo.fromJson({
        'version': '3.18.0',
        'frontendUrl': 'https://openshock.app',
        'oAuthProviders': ['discord', 'google'],
      });

      expect(info.oAuthProviders, ['discord', 'google']);
      expect(info.isOAuthAvailable, isTrue);
    });

    test('has no providers when the list is absent', () {
      final info = BackendInfo.fromJson({
        'version': '3.17.0',
        'frontendUrl': 'https://openshock.app',
      });

      expect(info.oAuthProviders, isEmpty);
      expect(info.isOAuthAvailable, isFalse);
    });

    test('skips entries that are not provider names', () {
      final info = BackendInfo.fromJson({
        'version': '3.18.0',
        'oAuthProviders': ['discord', '', 42, null],
      });

      expect(info.oAuthProviders, ['discord']);
    });

    test('is unavailable without a frontend URL', () {
      final info = BackendInfo.fromJson({
        'version': '3.18.0',
        'frontendUrl': '',
        'oAuthProviders': ['discord'],
      });

      expect(info.frontendUrl, isNull);
      expect(info.isOAuthAvailable, isFalse);
    });
  });
}
