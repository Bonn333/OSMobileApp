import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/backend_info.dart';

void main() {
  group('BackendInfo', () {
    // Shape taken from a live GET /1 response.
    Map<String, dynamic> live({Object? siteKey = '0x4AAAAAAARRD_J7SaOblZGy'}) {
      return {
        'version': '3.17.0',
        'commit': '46e3c9f3ae053dcfd5877152f5453a36426c5ece',
        'currentTime': '2026-08-31T16:08:40.271325+00:00',
        'frontendUrl': 'https://openshock.app',
        'shortLinkUrl': 'https://openshock.app',
        'turnstileSiteKey': siteKey,
        'oAuthProviders': ['discord', 'google'],
        'isMailEnabled': true,
        'isUserAuthenticated': false,
      };
    }

    test('parses a live response', () {
      final info = BackendInfo.fromJson(live());

      expect(info.version, '3.17.0');
      expect(info.frontendUrl, 'https://openshock.app');
      expect(info.turnstileSiteKey, '0x4AAAAAAARRD_J7SaOblZGy');
      expect(info.isTurnstileEnabled, isTrue);
    });

    // An instance with Turnstile switched off reports no site key. The login
    // screen has to notice this and skip the challenge rather than waiting
    // forever for a token that will never arrive.
    test('treats a missing site key as Turnstile disabled', () {
      expect(
        BackendInfo.fromJson(live(siteKey: null)).isTurnstileEnabled,
        isFalse,
      );
    });

    test('treats an empty site key as Turnstile disabled', () {
      final info = BackendInfo.fromJson(live(siteKey: ''));

      expect(info.turnstileSiteKey, isNull);
      expect(info.isTurnstileEnabled, isFalse);
    });

    test('tolerates a response missing optional fields', () {
      final info = BackendInfo.fromJson({'version': '1.0.0'});

      expect(info.version, '1.0.0');
      expect(info.frontendUrl, isNull);
      expect(info.isTurnstileEnabled, isFalse);
    });
  });
}
