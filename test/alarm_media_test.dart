import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ibada/alarms.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('app.ibada/alarms');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'reads and selects a bundled adhan without changing its label',
    () async {
      String? saved;
      const presets = {
        'adhan_medina': 'أذان المسجد النبوي',
        'adhan_classic': 'أذان آدم',
      };
      messenger.setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'mediaStatus':
            return {'soundPresets': presets, 'sound': presets[saved]};
          case 'setSoundPreset':
            saved = call.arguments as String?;
            return null;
          default:
            fail('Unexpected method: ${call.method}');
        }
      });

      final alarms = PrayerAlarms();
      expect((await alarms.media())!.soundPresets, presets);
      await alarms.changeMedia('setSoundPreset', 'adhan_medina');
      expect((await alarms.media())!.sound, 'أذان المسجد النبوي');
    },
  );

  test(
    'accepts a native media response without bundled adhan choices',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => {'soundPreset': true},
      );
      final media = (await PrayerAlarms().media())!;
      expect(media.soundPresets, isEmpty);
      expect(media.soundPreset, isTrue);
    },
  );
}
