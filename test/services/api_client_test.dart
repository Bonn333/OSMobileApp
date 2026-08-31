import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/services/api_client.dart';

import '../test_helpers.dart';

void main() {
  setUpFakeStorage();

  group('ApiClient', () {
    test('defaults to the official API host', () {
      expect(ApiClient.defaultBaseUrl, 'https://api.openshock.app');
      expect(ApiClient().baseUrl, isNotEmpty);
    });

    // Every caller has to share one instance: the session cookie jar lives on
    // this object, so a second instance would not be signed in.
    test('is a singleton', () {
      expect(identical(ApiClient(), ApiClient()), isTrue);
    });

    test('declares a non-empty User-Agent', () {
      // OpenShock blocks empty-User-Agent requests at the edge with a 403 whose
      // body is HTML rather than JSON.
      expect(ApiClient.userAgent, isNotEmpty);
    });

    // The name comes from the UserSessionCookie security scheme in the OpenAPI
    // document, and the SignalR hub is authenticated with the same value.
    test('uses the session cookie name from the API spec', () {
      expect(ApiClient.sessionCookieName, 'openShockSession');
    });

    test('changing the base URL keeps the client usable', () async {
      final client = ApiClient();
      final original = client.baseUrl;

      await client.setBaseUrl('https://api.example.invalid');
      expect(client.baseUrl, 'https://api.example.invalid');

      // setBaseUrl rebuilds Dio, so the cookie jar must survive the rebuild.
      expect(await client.cookieJar, isNotNull);

      await client.setBaseUrl(original);
      expect(client.baseUrl, original);
    });
  });
}
