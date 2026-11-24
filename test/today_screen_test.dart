import 'package:flutter_test/flutter_test.dart';
import 'package:ibada/app_theme.dart';
import 'package:ibada/prayer_times.dart';
import 'package:ibada/screens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  for (final layout in [
    (size: const Size(375, 780), scale: 1.0, brightness: Brightness.light),
    (size: const Size(320, 700), scale: 2.0, brightness: Brightness.dark),
    (size: const Size(780, 375), scale: 1.3, brightness: Brightness.light),
  ]) {
    testWidgets('Today fits ${layout.size} at ${layout.scale} text scale', (
      tester,
    ) async {
      tester.view
        ..physicalSize = layout.size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clock = ValueNotifier(DateTime.utc(2026, 11, 23, 12, 30));
      addTearDown(clock.dispose);
      var requested = false;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ibadaTheme(layout.brightness),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(layout.scale)),
            child: child!,
          ),
          home: Scaffold(
            body: TodayScreen(
              calculator: PrayerCalculator(PrayerSettings.defaults),
              today: DateTime.utc(2026, 11, 23),
              offset: 0,
              clock: clock,
              onLocation: () => requested = true,
              onAlerts: () {},
              onDay: (_) {},
              onPrayer: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('القاهرة'));
      expect(requested, isTrue);
      await tester.scrollUntilVisible(find.text('الصلاة القادمة'), 120);
      expect(find.text('الصلاة القادمة'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
