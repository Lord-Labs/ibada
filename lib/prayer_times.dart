import 'dart:math' as math;

import 'package:adhan_dart/adhan_dart.dart' as adhan;
// Check reachability before using Adhan 2.0.1's finite results for missing solar events.
// ignore: implementation_imports
import 'package:adhan_dart/src/SolarTime.dart';
import 'package:hijri_core/hijri_core.dart' as hijri;
import 'package:timezone/timezone.dart' as tz;

enum Prayer {
  fajr('الفجر'),
  sunrise('الشروق'),
  dhuhr('الظهر'),
  asr('العصر'),
  maghrib('المغرب'),
  isha('العشاء');

  const Prayer(this.label);
  final String label;
}

enum PrayerMethod {
  automatic('حسب البلد'),
  egypt('الهيئة المصرية العامة للمساحة'),
  makkah('أم القرى، مكة المكرمة'),
  league('رابطة العالم الإسلامي'),
  northAmerica('أمريكا الشمالية (ISNA)'),
  karachi('جامعة العلوم الإسلامية، كراتشي'),
  turkiye('رئاسة الشؤون الدينية التركية'),
  france('اتحاد مسلمي فرنسا'),
  morocco('وزارة الأوقاف المغربية'),
  algeria('وزارة الشؤون الدينية الجزائرية'),
  tunisia('تونس'),
  jordan('وزارة الأوقاف الأردنية'),
  kuwait('وزارة الأوقاف الكويتية'),
  qatar('قطر'),
  dubai('دبي'),
  indonesia('وزارة الشؤون الدينية الإندونيسية'),
  singapore('المجلس الإسلامي في سنغافورة'),
  jafari('معهد لواء، قم'),
  tehran('معهد الجيوفيزياء، طهران');

  const PrayerMethod(this.label);
  final String label;

  static PrayerMethod forCountry(String code) => switch (code) {
    'EG' || 'SD' => egypt,
    'SA' => makkah,
    'US' || 'CA' => northAmerica,
    'PK' || 'IN' || 'BD' || 'AF' => karachi,
    'TR' => turkiye,
    'FR' => france,
    'MA' => morocco,
    'DZ' => algeria,
    'TN' => tunisia,
    'JO' => jordan,
    'KW' => kuwait,
    'QA' => qatar,
    'AE' => dubai,
    'ID' => indonesia,
    'SG' => singapore,
    'IR' => tehran,
    _ => league,
  };

  adhan.CalculationParameters parameters() => switch (this) {
    egypt => adhan.CalculationMethodParameters.egyptian(),
    makkah => adhan.CalculationMethodParameters.ummAlQura(),
    northAmerica => adhan.CalculationMethodParameters.northAmerica(),
    karachi => adhan.CalculationMethodParameters.karachi(),
    turkiye => adhan.CalculationMethodParameters.turkiye(),
    france => adhan.CalculationMethodParameters.france(),
    morocco => adhan.CalculationMethodParameters.morocco(),
    algeria => adhan.CalculationMethodParameters.algerian(),
    tunisia => adhan.CalculationMethodParameters.tunisia(),
    jordan => adhan.CalculationMethodParameters.jordan(),
    kuwait => adhan.CalculationMethodParameters.kuwait(),
    qatar => adhan.CalculationMethodParameters.qatar(),
    dubai => adhan.CalculationMethodParameters.dubai(),
    indonesia => adhan.CalculationMethodParameters.indonesian(),
    singapore => adhan.CalculationMethodParameters.singapore(),
    jafari => adhan.CalculationMethodParameters.jafari(),
    tehran => adhan.CalculationMethodParameters.tehran(),
    automatic ||
    league => adhan.CalculationMethodParameters.muslimWorldLeague(),
  };
}

enum LatitudeRule {
  automatic('تلقائي حسب خط العرض'),
  seventh('سُبع الليل'),
  middle('منتصف الليل'),
  angle('نسبة زاوية الشفق');

  const LatitudeRule(this.label);
  final String label;
}

class Place {
  const Place(
    this.name,
    this.country,
    this.latitude,
    this.longitude,
    this.zone, {
    this.usesGps = false,
  });

  static const cairo = Place(
    'القاهرة',
    'EG',
    30.06263,
    31.24967,
    'Africa/Cairo',
  );
  final String name;
  final String country;
  final double latitude;
  final double longitude;
  final String zone;
  final bool usesGps;

  Map<String, Object> toJson() => {
    'name': name,
    'country': country,
    'latitude': latitude,
    'longitude': longitude,
    'zone': zone,
    'gps': usesGps,
  };

  factory Place.fromJson(Map<String, dynamic> json) => Place(
    json['name'] as String,
    json['country'] as String,
    (json['latitude'] as num).toDouble(),
    (json['longitude'] as num).toDouble(),
    json['zone'] as String,
    usesGps: json['gps'] == true,
  );
}

class PrayerSettings {
  const PrayerSettings({
    required this.place,
    this.method = PrayerMethod.automatic,
    this.latitudeRule = LatitudeRule.automatic,
    this.hanafi = false,
    this.enabled = const {
      Prayer.fajr,
      Prayer.dhuhr,
      Prayer.asr,
      Prayer.maghrib,
      Prayer.isha,
    },
    this.offsets = const {},
    this.alarms = false,
    this.confirmedPlace = false,
    this.fullScreen = true,
    this.use24Hour = false,
    this.appearance = 'system',
  });

  static const defaults = PrayerSettings(place: Place.cairo);
  final Place place;
  final PrayerMethod method;
  final LatitudeRule latitudeRule;
  final bool hanafi;
  final Set<Prayer> enabled;
  final Map<Prayer, int> offsets;
  final bool alarms;
  final bool confirmedPlace;
  final bool fullScreen;
  final bool use24Hour;
  final String appearance;

  PrayerMethod get resolvedMethod => method == PrayerMethod.automatic
      ? PrayerMethod.forCountry(place.country)
      : method;

  PrayerSettings copyWith({
    Place? place,
    PrayerMethod? method,
    LatitudeRule? latitudeRule,
    bool? hanafi,
    Set<Prayer>? enabled,
    Map<Prayer, int>? offsets,
    bool? alarms,
    bool? confirmedPlace,
    bool? fullScreen,
    bool? use24Hour,
    String? appearance,
  }) => PrayerSettings(
    place: place ?? this.place,
    method: method ?? this.method,
    latitudeRule: latitudeRule ?? this.latitudeRule,
    hanafi: hanafi ?? this.hanafi,
    enabled: enabled ?? this.enabled,
    offsets: offsets ?? this.offsets,
    alarms: alarms ?? this.alarms,
    confirmedPlace: confirmedPlace ?? this.confirmedPlace,
    fullScreen: fullScreen ?? this.fullScreen,
    use24Hour: use24Hour ?? this.use24Hour,
    appearance: appearance ?? this.appearance,
  );

  Map<String, Object> toJson() => {
    'place': place.toJson(),
    'method': method.name,
    'latitudeRule': latitudeRule.name,
    'hanafi': hanafi,
    'enabled': enabled.map((prayer) => prayer.name).toList(),
    'offsets': offsets.map((prayer, minutes) => MapEntry(prayer.name, minutes)),
    'alarms': alarms,
    'confirmedPlace': confirmedPlace,
    'fullScreen': fullScreen,
    'use24Hour': use24Hour,
    'appearance': appearance,
  };

  factory PrayerSettings.fromJson(Map<String, dynamic> json) => PrayerSettings(
    place: Place.fromJson(json['place'] as Map<String, dynamic>),
    method:
        PrayerMethod.values.asNameMap()[json['method']] ??
        PrayerMethod.automatic,
    latitudeRule:
        LatitudeRule.values.asNameMap()[json['latitudeRule']] ??
        LatitudeRule.automatic,
    hanafi: json['hanafi'] == true,
    enabled: json['enabled'] is List
        ? Prayer.values
              .where(
                (prayer) => (json['enabled'] as List).contains(prayer.name),
              )
              .toSet()
        : defaults.enabled,
    offsets: {
      for (final prayer in Prayer.values)
        if (json['offsets']?[prayer.name] is int)
          prayer: (json['offsets'][prayer.name] as int).clamp(-30, 30),
    },
    alarms: json['alarms'] == true,
    confirmedPlace: json['confirmedPlace'] == true,
    fullScreen: json['fullScreen'] != false,
    use24Hour: json['use24Hour'] == true,
    appearance: json['appearance'] as String? ?? 'system',
  );
}

typedef PrayerEvent = ({Prayer prayer, tz.TZDateTime time});
typedef PrayerDay = ({DateTime day, List<PrayerEvent> events, bool estimated});

DateTime civilKey(DateTime date, [int offset = 0]) =>
    DateTime.utc(date.year, date.month, date.day + offset);

class PrayerCalculator {
  PrayerCalculator(this.settings)
    : location = tz.getLocation(settings.place.zone);

  final PrayerSettings settings;
  final tz.Location location;
  final _days = <DateTime, PrayerDay>{};
  final _sun = <DateTime, ({DateTime date, SolarTime times, bool estimated})>{};

  tz.TZDateTime localTime(DateTime instant) =>
      tz.TZDateTime.from(instant, location);

  DateTime _time(DateTime date, double hour) =>
      date.add(Duration(seconds: (hour * 3600).floor()));

  bool _crossesAltitude(SolarTime sun, double angle) {
    const radians = math.pi / 180;
    final latitude = sun.observer.latitude * radians;
    final declination = sun.solar.declination! * radians;
    final cosine =
        (math.sin(angle * radians) -
            math.sin(latitude) * math.sin(declination)) /
        (math.cos(latitude) * math.cos(declination));
    return cosine.abs() <= 1;
  }

  ({DateTime date, SolarTime times, bool estimated}) _solarFor(DateTime day) =>
      _sun.putIfAbsent(day, () {
        final place = settings.place;
        var date = day;
        var latitude = place.latitude.clamp(-89.5, 89.5);
        SolarTime solar() =>
            SolarTime(date, adhan.Coordinates(latitude, place.longitude));
        var times = solar();
        final noon = localTime(_time(date, times.transit));
        if (civilKey(noon) != day) {
          date = date.add(day.difference(civilKey(noon)));
          times = solar();
        }
        while (!_crossesAltitude(times, -50 / 60) ||
            !times.sunrise.isFinite ||
            !times.sunset.isFinite ||
            times.transit - times.sunrise <= 0 ||
            times.sunset - times.transit <= 0 ||
            times.transit - times.sunrise > 12.5 ||
            times.sunset - times.transit > 12.5) {
          latitude -= latitude.sign * .5;
          times = solar();
        }
        return (
          date: date,
          times: times,
          estimated: latitude != place.latitude,
        );
      });

  PrayerDay forDay(DateTime date) {
    final day = civilKey(date);
    return _days.putIfAbsent(day, () {
      final today = _solarFor(day);
      final yesterday = _solarFor(civilKey(day, -1));
      final tomorrow = _solarFor(civilKey(day, 1));
      final sun = today.times;
      final rise = _time(today.date, sun.sunrise);
      final set = _time(today.date, sun.sunset);
      final lastSet = _time(yesterday.date, yesterday.times.sunset);
      final nextRise = _time(tomorrow.date, tomorrow.times.sunrise);
      final params = settings.resolvedMethod.parameters();
      params.highLatitudeRule = switch (settings.latitudeRule) {
        LatitudeRule.automatic =>
          settings.place.latitude.abs() > 48
              ? adhan.HighLatitudeRule.seventhOfTheNight
              : adhan.HighLatitudeRule.middleOfTheNight,
        LatitudeRule.middle => adhan.HighLatitudeRule.middleOfTheNight,
        LatitudeRule.seventh => adhan.HighLatitudeRule.seventhOfTheNight,
        LatitudeRule.angle => adhan.HighLatitudeRule.twilightAngle,
      };
      final portions = params.nightPortions();
      final fajrAngle = sun.hourAngle(-params.fajrAngle, false);
      final ishaAngle = sun.hourAngle(-params.ishaAngle, true);
      final hasFajr =
          _crossesAltitude(sun, -params.fajrAngle) &&
          fajrAngle.isFinite &&
          fajrAngle < sun.sunrise &&
          sun.sunrise - fajrAngle < 12;
      final hasIsha =
          _crossesAltitude(sun, -params.ishaAngle) &&
          ishaAngle.isFinite &&
          ishaAngle > sun.sunset &&
          ishaAngle - sun.sunset < 12;
      final safeFajr = rise.subtract(
        Duration(
          seconds:
              (math.max(0, rise.difference(lastSet).inSeconds) *
                      portions[adhan.Prayer.fajr]!)
                  .round(),
        ),
      );
      final safeIsha = set.add(
        Duration(
          seconds:
              (math.max(0, nextRise.difference(set).inSeconds) *
                      portions[adhan.Prayer.isha]!)
                  .round(),
        ),
      );
      final solarFajr = hasFajr ? _time(today.date, fajrAngle) : safeFajr;
      final solarIsha = hasIsha ? _time(today.date, ishaAngle) : safeIsha;
      final fajr = solarFajr.isBefore(safeFajr) ? safeFajr : solarFajr;
      final ramadanEvening =
          settings.resolvedMethod == PrayerMethod.makkah &&
          hijri.toHijri(civilKey(day, 1))?.hm == 9;
      final fixedIsha = ramadanEvening ? 120 : (params.ishaInterval ?? 0);
      final isha = fixedIsha > 0
          ? set.add(Duration(minutes: fixedIsha))
          : (solarIsha.isAfter(safeIsha) ? safeIsha : solarIsha);
      final maghribAngle = sun.hourAngle(-(params.maghribAngle ?? 0), true);
      final twilight =
          _crossesAltitude(sun, -(params.maghribAngle ?? 0)) &&
              maghribAngle.isFinite
          ? _time(today.date, maghribAngle)
          : set;
      final maghrib =
          params.maghribAngle != null &&
              twilight.isAfter(set) &&
              twilight.isBefore(isha)
          ? twilight
          : set;
      final afternoon = sun.afternoon(settings.hanafi ? 2 : 1);
      final hasAsr =
          afternoon.isFinite &&
          afternoon > sun.transit &&
          afternoon < sun.sunset;
      final asr = _time(
        today.date,
        hasAsr ? afternoon : (sun.transit + sun.sunset) / 2,
      );
      final times = [
        fajr,
        rise,
        _time(today.date, sun.transit),
        asr,
        maghrib,
        isha,
      ];
      return (
        day: day,
        estimated:
            today.estimated ||
            yesterday.estimated ||
            tomorrow.estimated ||
            !hasFajr ||
            !hasAsr ||
            (fixedIsha == 0 && !hasIsha),
        events: [
          for (final prayer in Prayer.values)
            (
              prayer: prayer,
              time: _adjust(prayer, times[prayer.index], params),
            ),
        ],
      );
    });
  }

  tz.TZDateTime _adjust(
    Prayer prayer,
    DateTime time,
    adhan.CalculationParameters params,
  ) {
    final adhanPrayer = adhan.Prayer.values.byName(prayer.name);
    final seconds = time.millisecondsSinceEpoch / 1000;
    final rounded = switch (params.rounding) {
      adhan.Rounding.up => (seconds / 60).ceil() * 60,
      adhan.Rounding.nearest => (seconds / 60).round() * 60,
      adhan.Rounding.none => seconds.toInt(),
    };
    final correction =
        (settings.offsets[prayer] ?? 0) +
        (params.methodAdjustments[adhanPrayer] ?? 0);
    return localTime(
      DateTime.fromMillisecondsSinceEpoch(
        (rounded + correction * 60) * Duration.millisecondsPerSecond,
        isUtc: true,
      ),
    );
  }

  List<PrayerEvent> _ordered(DateTime first, int count) => [
    for (var i = 0; i < count; i++)
      ...forDay(
        civilKey(first, i),
      ).events.where((event) => event.prayer != Prayer.sunrise),
  ]..sort((a, b) => a.time.compareTo(b.time));

  ({PrayerEvent previous, PrayerEvent next, double progress}) at(DateTime now) {
    final events = _ordered(civilKey(localTime(now), -1), 3);
    final next = events.indexWhere((event) => event.time.isAfter(now));
    final previous = events[math.max(0, next - 1)];
    final upcoming = events[next < 0 ? events.length - 1 : next];
    final total = upcoming.time.difference(previous.time).inSeconds;
    final elapsed = now.difference(previous.time).inSeconds;
    return (
      previous: previous,
      next: upcoming,
      progress: total <= 0 ? 0 : (elapsed / total).clamp(0.0, 1.0),
    );
  }

  List<PrayerEvent> upcomingAlerts(DateTime now, int days) =>
      _ordered(civilKey(localTime(now), -1), days + 1)
          .where(
            (event) =>
                settings.enabled.contains(event.prayer) &&
                event.time.isAfter(now),
          )
          .toList();
}
