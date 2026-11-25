import 'package:flutter_test/flutter_test.dart';
import 'package:ibada/devotion.dart';
import 'package:ibada/local_data.dart';
import 'package:ibada/main.dart';
import 'package:ibada/prayer_times.dart';
import 'package:ibada/screens.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

class _LocalData extends LocalData {
  @override
  Future<bool> refreshTimeZones(String activeZone) async => false;
}

void main() {
  setUpAll(tzdata.initializeTimeZones);

  testWidgets('Today links to the week and the new tabs stay easy to reach', (
    tester,
  ) async {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);

    tester.view
      ..physicalSize = const Size(375, 780)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      IbadaApp(data: _LocalData(), settings: PrayerSettings.defaults),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('جدول الأسبوع'), 120);
    await tester.tap(find.text('جدول الأسبوع'));
    await tester.pumpAndSettle();
    expect(find.byType(WeekScreen), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text('الأذكار'));
    await tester.pumpAndSettle();
    expect(find.byType(AdhkarScreen), findsOneWidget);
    await tester.tap(find.text('السبحة'));
    await tester.pumpAndSettle();
    expect(find.byType(TasbeehScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layout keeps navigation and the counter reachable', (
    tester,
  ) async {
    final previous = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    addTearDown(() => SharedPreferencesAsyncPlatform.instance = previous);

    tester.view
      ..physicalSize = const Size(812, 360)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      IbadaApp(data: _LocalData(), settings: PrayerSettings.defaults),
    );
    await tester.pumpAndSettle();

    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    await tester.tap(find.descendant(of: rail, matching: find.text('السبحة')));
    await tester.pumpAndSettle();
    final count = find.text('اضغط للتسبيح');
    expect(count.hitTestable(), findsOneWidget);
    await tester.tap(count);
    await tester.pumpAndSettle();
    expect(find.text('١ من ٣٣').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
