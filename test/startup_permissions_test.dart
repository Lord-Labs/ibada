import 'package:flutter_test/flutter_test.dart';
import 'package:ibada/local_data.dart';
import 'package:ibada/prayer_times.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  SharedPreferencesAsyncPlatform? previousPlatform;

  setUp(() {
    previousPlatform = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  tearDown(() => SharedPreferencesAsyncPlatform.instance = previousPlatform);

  test(
    'a fresh install requests startup permissions once across launches',
    () async {
      expect(await LocalData().claimStartupPermissions(), isTrue);
      expect(await LocalData().claimStartupPermissions(), isFalse);
    },
  );

  test(
    'updating an existing install skips automatic permission prompts',
    () async {
      final data = LocalData();
      await data.save(PrayerSettings.defaults.copyWith(confirmedPlace: true));

      expect(await data.claimStartupPermissions(), isFalse);
    },
  );
}
