import 'package:flutter_test/flutter_test.dart';
import 'package:openshock_mobile/models/lcg_info.dart';

void main() {
  group('LcgInfo', () {
    test('parses the gateway response', () {
      final info = LcgInfo.fromJson({
        'host': 'de1-gateway.openshock.app',
        'port': 443,
        'pathPrefix': '/1',
        'country': 'DE',
      });

      expect(info.host, 'de1-gateway.openshock.app');
      expect(info.port, 443);
      expect(info.pathPrefix, '/1');
      expect(info.country, 'DE');
    });

    test('builds the live socket url', () {
      final info = LcgInfo.fromJson({
        'host': 'de1-gateway.openshock.app',
        'port': 443,
        'pathPrefix': '',
        'country': 'DE',
      });

      expect(
        info.liveSocketUri('abc-123').toString(),
        'wss://de1-gateway.openshock.app/1/ws/live/abc-123',
      );
    });

    test('keeps the gateway path prefix without doubling slashes', () {
      final info = LcgInfo.fromJson({
        'host': 'gw.example.com',
        'port': 443,
        'pathPrefix': '/lcg/',
        'country': 'DE',
      });

      expect(
        info.liveSocketUri('hub').toString(),
        'wss://gw.example.com/lcg/1/ws/live/hub',
      );
    });

    test('keeps a non-default port', () {
      final info = LcgInfo.fromJson({
        'host': 'localhost',
        'port': 5001,
        'pathPrefix': '',
        'country': 'DE',
      });

      expect(
        info.liveSocketUri('hub').toString(),
        'wss://localhost:5001/1/ws/live/hub',
      );
    });

    test('uses ws for a plain http port', () {
      final info = LcgInfo.fromJson({
        'host': 'localhost',
        'port': 80,
        'pathPrefix': '',
        'country': 'DE',
      });

      expect(info.liveSocketUri('hub').scheme, 'ws');
    });
  });
}
