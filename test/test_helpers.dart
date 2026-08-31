import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const MethodChannel _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void setUpFakeStorage({Map<String, String> initialSecureValues = const {}}) {
  TestWidgetsFlutterBinding.ensureInitialized();

  final store = Map<String, String>.from(initialSecureValues);

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async {
          final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
          final key = args['key'] as String?;

          switch (call.method) {
            case 'read':
              return key == null ? null : store[key];
            case 'readAll':
              return Map<String, String>.from(store);
            case 'write':
              if (key != null) store[key] = args['value'] as String? ?? '';
              return null;
            case 'delete':
              if (key != null) store.remove(key);
              return null;
            case 'deleteAll':
              store.clear();
              return null;
            case 'containsKey':
              return key != null && store.containsKey(key);
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
    store.clear();
  });
}
