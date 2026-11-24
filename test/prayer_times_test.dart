import 'package:flutter_test/flutter_test.dart';
import 'package:ibada/prayer_times.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test(
    'Cairo prayer times track civil time through the end of Egyptian DST',
    () {
      final calculator = PrayerCalculator(PrayerSettings.defaults);
      final before = calculator.forDay(DateTime.utc(2026, 10, 29));
      final after = calculator.forDay(DateTime.utc(2026, 10, 30));
      final dhuhr = Prayer.dhuhr.index;
      expect(
        before.events[dhuhr].time.timeZoneOffset,
        const Duration(hours: 3),
      );
      expect(after.events[dhuhr].time.timeZoneOffset, const Duration(hours: 2));
      expect(
        after.events[dhuhr].time
            .toUtc()
            .difference(before.events[dhuhr].time.toUtc())
            .inHours,
        inInclusiveRange(23, 24),
      );
      expect(after.events[dhuhr].time.hour, 11);
    },
  );

  test('after Isha the next event is tomorrow’s Fajr', () {
    final calculator = PrayerCalculator(PrayerSettings.defaults);
    final now = DateTime.utc(2026, 11, 23, 21, 30);
    final state = calculator.at(now);
    expect(state.previous.prayer, Prayer.isha);
    expect(state.next.prayer, Prayer.fajr);
    expect(state.next.time.day, 24);
    expect(state.next.time.isAfter(now), isTrue);
  });

  test('location civil date can differ from UTC date', () {
    final calculator = PrayerCalculator(
      PrayerSettings.defaults.copyWith(
        place: const Place('أوكلاند', 'NZ', -36.85, 174.76, 'Pacific/Auckland'),
      ),
    );
    final now = DateTime.utc(2026, 11, 23, 11, 30);
    expect(calculator.localTime(now).day, 24);
    expect(
      calculator.forDay(calculator.localTime(now)).events.first.time.day,
      24,
    );
  });

  test('polar winter gets an explicitly estimated ordered timetable', () {
    final calculator = PrayerCalculator(
      PrayerSettings.defaults.copyWith(
        place: const Place('ترومسو', 'NO', 69.65, 18.96, 'Europe/Oslo'),
      ),
    );
    final day = calculator.forDay(DateTime.utc(2026, 12, 21));
    expect(day.estimated, isTrue);
    expect(day.events.length, 6);
    for (var i = 1; i < day.events.length; i++) {
      expect(day.events[i].time.isAfter(day.events[i - 1].time), isTrue);
    }
  });

  test(
    'Arctic summer keeps the actual sunrise and estimates missing twilight',
    () {
      final calculator = PrayerCalculator(
        PrayerSettings.defaults.copyWith(
          place: const Place(
            'ريكيافيك',
            'IS',
            64.1466,
            -21.9426,
            'Atlantic/Reykjavik',
          ),
        ),
      );
      final day = calculator.forDay(DateTime.utc(2026, 6, 21));
      expect(day.estimated, isTrue);
      expect(
        day.events[Prayer.sunrise.index].time.hour,
        inInclusiveRange(2, 4),
      );
      expect(
        day.events[Prayer.isha.index].time.isAfter(
          day.events[Prayer.maghrib.index].time,
        ),
        isTrue,
      );
    },
  );

  test(
    'solar noon follows the civil date west of the International Date Line',
    () {
      final calculator = PrayerCalculator(
        PrayerSettings.defaults.copyWith(
          place: const Place(
            'كيريتيماتي',
            'KI',
            1.8721,
            -157.4278,
            'Pacific/Kiritimati',
          ),
        ),
      );
      final day = calculator.forDay(DateTime.utc(2026, 11, 23));
      final dhuhr = day.events[Prayer.dhuhr.index].time;
      expect(dhuhr.day, 23);
      expect(dhuhr.hour, inInclusiveRange(11, 13));
    },
  );

  test('Umm al-Qura observes the Ramadan evening interval', () {
    final calculator = PrayerCalculator(
      PrayerSettings.defaults.copyWith(
        place: const Place(
          'مكة المكرمة',
          'SA',
          21.4225,
          39.8262,
          'Asia/Riyadh',
        ),
      ),
    );
    Duration between(DateTime date) {
      final day = calculator.forDay(date);
      return day.events[Prayer.isha.index].time.difference(
        day.events[Prayer.maghrib.index].time,
      );
    }

    expect(between(DateTime.utc(2026, 3, 1)), const Duration(hours: 2));
    expect(between(DateTime.utc(2026, 11, 23)), const Duration(minutes: 90));
  });

  test(
    'a user correction changes only its prayer and sunrise never alarms',
    () {
      final original = PrayerCalculator(PrayerSettings.defaults);
      final settings = PrayerSettings.defaults.copyWith(
        offsets: {Prayer.fajr: 3},
        enabled: {Prayer.fajr, Prayer.sunrise},
      );
      final adjusted = PrayerCalculator(settings);
      final now = DateTime.utc(2026, 11, 23, 1);
      final base = original.forDay(now).events;
      final changes = adjusted.forDay(now).events;
      expect(changes.first.time.difference(base.first.time).inMinutes, 3);
      expect(changes[1].time, base[1].time);
      expect(
        adjusted.upcomingAlerts(now, 3).map((event) => event.prayer),
        everyElement(Prayer.fajr),
      );
      expect(adjusted.upcomingAlerts(now, 3), hasLength(3));
    },
  );
}
