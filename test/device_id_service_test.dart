import 'package:flutter_test/flutter_test.dart';
import 'package:replica_detector/services/device_id_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('uses the platform id when there is one, and keeps returning it', () async {
    var calls = 0;
    final svc = DeviceIdService(platformId: () async {
      calls++;
      return 'android-id-abcdef12';
    });
    expect(await svc.id(), 'android-id-abcdef12');
    expect(await svc.id(), 'android-id-abcdef12');
    expect(calls, 1);
  });

  test('falls back to one random id kept on the phone when the platform has none', () async {
    final a = DeviceIdService(platformId: () async => null);
    final first = await a.id();
    expect(first, startsWith('app-'));
    expect(first.length, greaterThanOrEqualTo(8));
    // a new service object (like a new app start) gets the same id back
    final b = DeviceIdService(platformId: () async => null);
    expect(await b.id(), first);
  });

  test('a blank, too-short or placeholder platform id is not used', () async {
    for (final bad in ['', 'abc', '9774d56d682e549c']) {
      SharedPreferences.setMockInitialValues({});
      final id = await DeviceIdService(platformId: () async => bad).id();
      expect(id, startsWith('app-'), reason: bad);
    }
  });

  test('a platform error falls back too', () async {
    final id = await DeviceIdService(platformId: () async => throw Exception('no channel')).id();
    expect(id, startsWith('app-'));
  });
}
