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
}
