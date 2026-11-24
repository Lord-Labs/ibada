import 'dart:io';

import 'package:flutter/services.dart';

import 'prayer_times.dart';

typedef AlarmStatus = ({
  bool supported,
  bool notifications,
  bool exact,
  bool fullScreen,
  bool alarmKit,
});

class PrayerAlarms {
  static const _channel = MethodChannel('app.ibada/alarms');

  static const unknown = (
    supported: false,
    notifications: false,
    exact: false,
    fullScreen: false,
    alarmKit: false,
  );

  Future<AlarmStatus> status() async {
    final state = await _channel.invokeMapMethod<String, bool>('status');
    return state == null
        ? unknown
        : (
            supported: true,
            notifications: state['notifications'] ?? false,
            exact: state['exact'] ?? false,
            fullScreen: state['fullScreen'] ?? false,
            alarmKit: state['alarmKit'] ?? false,
          );
  }

  Future<void> request(String permission) =>
      _channel.invokeMethod<void>('request', permission);

  Future<void> replace(PrayerCalculator calculator, DateTime now) async {
    final settings = calculator.settings;
    final events = settings.alarms && settings.confirmedPlace
        ? calculator.upcomingAlerts(
            now.subtract(const Duration(minutes: 2)),
            400,
          )
        : <PrayerEvent>[];
    await _channel.invokeMethod<void>('replace', {
      'fullScreen': settings.fullScreen,
      'events': [
        for (final event in events)
          {
            'time': event.time.millisecondsSinceEpoch,
            'label': event.prayer.label,
            'prayer': event.prayer.index,
          },
      ],
    });
  }

  Future<void> test(bool fullScreen) =>
      _channel.invokeMethod<void>('test', fullScreen);

  bool get supported => Platform.isAndroid || Platform.isIOS;
}
