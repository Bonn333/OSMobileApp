import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/lcg_info.dart';

void main() {
  // v2 returns the gateway object directly. v1 wrapped it in {message, data},
  // and reading a v2 body with the v1 extractor is what produced
  // "Unexpected response format" when live control was first wired up.
  group('LCG response shape', () {
    const bareV2 = {
      'host': 'de1-gateway.openshock.app',
      'port': 443,
      'pathPrefix': '',
      'country': 'DE',
    };

    test('parses the bare v2 body', () {
      final info = LcgInfo.fromJson(bareV2);

      expect(info.host, 'de1-gateway.openshock.app');
      expect(
        info.liveSocketUri('hub').toString(),
        'wss://de1-gateway.openshock.app/1/ws/live/hub',
      );
    });

    test('a v1 envelope is not itself a gateway object', () {
      const enveloped = {'message': 'OpenShock', 'data': bareV2};

      expect(enveloped.containsKey('host'), isFalse);
      expect(enveloped['data'], bareV2);
    });
  });
}
