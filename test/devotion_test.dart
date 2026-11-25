import 'package:flutter_test/flutter_test.dart';
import 'package:ibada/app_theme.dart';
import 'package:ibada/devotion.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  SharedPreferencesAsyncPlatform? originalPreferences;
  setUp(() {
    originalPreferences = SharedPreferencesAsyncPlatform.instance;
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = originalPreferences);

  testWidgets('adhkar resumes partial reading without changing other groups', (
    tester,
  ) async {
    await _show(tester, const AdhkarScreen());
    await tester.tap(find.text('أذكار الصباح'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عدّ مرة'));
    await tester.pumpAndSettle();
    expect(find.text('١ من ٣ مرات'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await _show(tester, const SizedBox());
    await _show(tester, const AdhkarScreen());
    await tester.tap(find.text('أذكار المساء'));
    await tester.pumpAndSettle();
    expect(find.text('٠ من ٣ مرات'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أذكار الصباح'));
    await tester.pumpAndSettle();
    expect(find.text('١ من ٣ مرات'), findsOneWidget);
  });

  testWidgets('prayer selection keeps each reading session independent', (
    tester,
  ) async {
    await _show(tester, const AdhkarScreen());
    await tester.tap(find.text('أذكار بعد الصلاة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الفجر'));
    await tester.pumpAndSettle();
    expect(find.text('بعد صلاة الفجر'), findsOneWidget);
    await tester.tap(find.text('عدّ مرة'));
    await tester.pumpAndSettle();
    expect(find.text('١ من ٣ مرات'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('أذكار بعد الصلاة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('الظهر'));
    await tester.pumpAndSettle();
    expect(find.text('٠ من ٣ مرات'), findsOneWidget);
  });

  testWidgets('tasbeeh keeps the count and target when reopened', (
    tester,
  ) async {
    await _show(tester, const TasbeehScreen());
    await tester.tap(find.text('٩٩'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اضغط للتسبيح'));
    await tester.pumpAndSettle();

    await _show(tester, const SizedBox());
    await _show(tester, const TasbeehScreen());
    expect(find.text('١ من ٩٩'), findsOneWidget);
    await tester.tap(find.text('تصفير العدّ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('تصفير'));
    await tester.pumpAndSettle();
    expect(find.text('٠ من ٩٩'), findsOneWidget);
  });

  testWidgets('devotion screens fit at double text size on a narrow device', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(320, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _show(tester, const AdhkarScreen(), scale: 2);
    await tester.tap(find.text('أذكار الصباح'));
    await tester.pumpAndSettle();
    final countButton = find.text('عدّ مرة');
    expect(countButton.hitTestable(), findsOneWidget);
    final countPosition = tester.getCenter(countButton);
    expect(countPosition.dy, greaterThan(540));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.getCenter(countButton), countPosition);
    expect(tester.takeException(), isNull);

    for (var repetition = 0; repetition < 3; repetition++) {
      await tester.tap(countButton);
      await tester.pumpAndSettle();
    }
    expect(find.text('تم الذكر'), findsOneWidget);
    await tester.tap(find.text('التالي'));
    await tester.pumpAndSettle();
    expect(find.text('الذكر ٢ من ٧'), findsOneWidget);
    await tester.tap(find.byTooltip('قائمة الأذكار'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بسم الله الذي لا يضر'));
    await tester.pumpAndSettle();
    expect(find.text('تم الذكر'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    await _show(tester, const TasbeehScreen(), scale: 2);
    final tapTarget = find.widgetWithText(FilledButton, 'اضغط للتسبيح');
    expect(tapTarget.hitTestable(), findsOneWidget);
    expect(tester.getRect(tapTarget).height, greaterThanOrEqualTo(48));
    expect(tester.getCenter(tapTarget).dy, greaterThan(540));
    for (var repetition = 0; repetition < 2; repetition++) {
      await tester.tap(tapTarget);
    }
    await tester.pumpAndSettle();
    expect(find.text('٢ من ٣٣'), findsOneWidget);
    await tester.tap(find.byTooltip('التراجع عن آخر عدّة'));
    await tester.pumpAndSettle();
    expect(find.text('١ من ٣٣'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _show(
  WidgetTester tester,
  Widget screen, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ibadaTheme(scale == 1 ? Brightness.light : Brightness.dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(body: screen),
    ),
  );
  await tester.pumpAndSettle();
}
