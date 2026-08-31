import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/services/api_client.dart';

void main() {
  group('ApiClient', () {
    // The client is a singleton, so state set by one test leaks into the next.
    tearDown(() async => ApiClient().setApiToken(null));

    test('defaults to the official API host', () {
      expect(ApiClient.defaultBaseUrl, 'https://api.openshock.app');
      expect(ApiClient().baseUrl, isNotEmpty);
    });

    // Every caller has to share one instance: the token lives in memory, so a
    // second instance would simply be unauthenticated.
    test('is a singleton', () {
      expect(identical(ApiClient(), ApiClient()), isTrue);
    });

    test('declares a non-empty User-Agent', () {
      // OpenShock blocks empty-User-Agent requests at the edge with a 403 whose
      // body is HTML rather than JSON.
      expect(ApiClient.userAgent, isNotEmpty);
    });

    test('starts with no token attached', () {
      expect(ApiClient().apiToken, isNull);
    });

    test('attaches and clears the API token', () async {
      final client = ApiClient();

      await client.setApiToken('token-abc');
      expect(client.apiToken, 'token-abc');

      await client.setApiToken(null);
      expect(client.apiToken, isNull);
    });

    test('treats an empty token as no token', () async {
      final client = ApiClient();

      await client.setApiToken('');
      expect(client.apiToken, isNull);
    });

    test('keeps the token across a base URL change', () async {
      // setBaseUrl rebuilds the underlying Dio instance, which would drop the
      // auth header if the token were not re-applied.
      final client = ApiClient();
      final original = client.baseUrl;

      await client.setApiToken('token-abc');
      await client.setBaseUrl('https://api.example.invalid');

      expect(client.baseUrl, 'https://api.example.invalid');
      expect(client.apiToken, 'token-abc');

      await client.setBaseUrl(original);
    });
  });
}
