import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/lcg_info.dart';

void main() {
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
