import BackgroundTasks
import Flutter
import SwiftUI
import UIKit
import UserNotifications

#if canImport(AlarmKit)
import AlarmKit
#endif

private struct ScheduledPrayer: Codable {
  let time: Int64
  let label: String
  let index: Int

  var date: Date { Date(timeIntervalSince1970: Double(time) / 1_000) }
  var id: UUID {
    UUID(uuidString: "32686CDD-E126-4BE6-\(String(format: "%04x", index))-\(String(format: "%012llx", time))")!
  }
  var title: String { index == 9 ? label : "حان وقت صلاة \(label)" }
  var notificationID: String { "ibada-\(id.uuidString)" }
}

@available(iOS 15.0, *)
@MainActor
final class PrayerAlarmBridge {
  private let center = UNUserNotificationCenter.current()
  private let defaults = UserDefaults.standard
  private let planKey = "ibada-prayer-plan"
  private let refreshID = "app.ibada.refresh"
  private var operation: Task<Void, Never>?

  func attach(to messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "app.ibada/alarms", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        Task { @MainActor in self?.handle(call, result: result) }
      }
  }

  func registerBackgroundRefresh() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: .main) { [weak self] task in
      Task { @MainActor in self?.backgroundRefresh(task) }
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let previous = operation
    operation = Task {
      await previous?.value
      do {
        switch call.method {
        case "status":
          let permitted = await notificationsAllowed()
          let alarm = alarmKitStatus()
          result(["notifications": permitted, "exact": alarm.authorized,
                  "fullScreen": alarm.authorized, "alarmKit": alarm.available])
        case "request":
          try await request(call.arguments as? String)
          result(nil)
        case "replace":
          guard let args = call.arguments as? [String: Any],
                let rows = args["events"] as? [[String: Any]] else {
            throw CocoaError(.coderInvalidValue)
          }
          let plan = rows.compactMap { row -> ScheduledPrayer? in
            guard let time = row["time"] as? NSNumber, let label = row["label"] as? String,
                  let index = row["prayer"] as? Int else { return nil }
            return ScheduledPrayer(time: time.int64Value, label: label, index: index)
          }
          defaults.set(try JSONEncoder().encode(plan), forKey: planKey)
          try await apply(plan)
          scheduleRefresh(ifNeeded: !plan.isEmpty)
          result(nil)
        case "test":
          let event = ScheduledPrayer(time: Int64(Date().timeIntervalSince1970 * 1_000) + 15_000,
                                      label: "تنبيه تجريبي", index: 9)
          if alarmKitStatus().authorized {
            try await scheduleAlarmKitTest(event)
          } else {
            guard await notificationsAllowed() else { throw CocoaError(.userCancelled) }
            try await center.add(notification(event))
          }
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "PRAYER_ALARM", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func notificationsAllowed() async -> Bool {
    let status = await center.notificationSettings().authorizationStatus
    return status == .authorized || status == .provisional
  }

  private func request(_ permission: String?) async throws {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *), permission == "exact" {
        let manager = AlarmManager.shared
        if manager.authorizationState == .denied {
          openSettings()
        } else if manager.authorizationState == .notDetermined {
          _ = try await manager.requestAuthorization()
        }
        return
      }
    #endif
    switch await center.notificationSettings().authorizationStatus {
    case .denied:
      if permission != "startupNotifications" { openSettings() }
    case .notDetermined:
      _ = try await center.requestAuthorization(options: [.alert, .sound])
    default:
      break
    }
  }

  private func openSettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
  }

  private func alarmKitStatus() -> (available: Bool, authorized: Bool) {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        return (true, AlarmManager.shared.authorizationState == .authorized)
      }
    #endif
    return (false, false)
  }

  private func apply(_ plan: [ScheduledPrayer]) async throws {
    let future = plan.filter { $0.date > Date() }
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *), alarmKitStatus().authorized {
        let manager = AlarmManager.shared
        let native = Array(future.prefix(25))
        do {
          let existing = try manager.alarms
          let wanted = Set(native.map(\.id))
          for alarm in existing where alarm.state == .scheduled && !wanted.contains(alarm.id) &&
              !alarm.id.uuidString.contains("-0009-") {
            try manager.cancel(id: alarm.id)
          }
          let scheduled = Set(existing.map(\.id))
          for event in native where !scheduled.contains(event.id) {
            try await addNative(event)
          }
          let fallback = await notificationsAllowed() ? Array(future.dropFirst(25).prefix(60)) : []
          try await applyNotifications(fallback)
          return
        } catch {
          for alarm in try manager.alarms where alarm.state == .scheduled &&
              !alarm.id.uuidString.contains("-0009-") {
            try manager.cancel(id: alarm.id)
          }
          if !(await notificationsAllowed()) { throw error }
        }
      }
    #endif
    try await applyNotifications(await notificationsAllowed() ? Array(future.prefix(60)) : [])
  }

  private func applyNotifications(_ wanted: [ScheduledPrayer]) async throws {
    let pending = await center.pendingNotificationRequests()
      .map(\.identifier).filter { $0.hasPrefix("ibada-") && !$0.contains("-0009-") }
    let next = Set(wanted.map(\.notificationID))
    center.removePendingNotificationRequests(withIdentifiers: pending.filter { !next.contains($0) })
    let existing = Set(pending)
    for event in wanted where !existing.contains(event.notificationID) {
      try await center.add(notification(event))
    }
  }

  private func notification(_ event: ScheduledPrayer) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = event.title
    content.body = "عبادة"
    content.sound = .default
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let components = calendar.dateComponents([.calendar, .year, .month, .day, .hour, .minute, .second, .timeZone],
                                             from: event.date)
    return UNNotificationRequest(identifier: event.notificationID, content: content,
                                 trigger: UNCalendarNotificationTrigger(dateMatching: components,
                                                                       repeats: false))
  }

  private func scheduleAlarmKitTest(_ event: ScheduledPrayer) async throws {
    #if canImport(AlarmKit)
      if #available(iOS 26.0, *) {
        try await addNative(event)
      }
    #endif
  }

  #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private struct Metadata: AlarmMetadata {}

    @available(iOS 26.0, *)
    private func addNative(_ event: ScheduledPrayer) async throws {
      let title = LocalizedStringResource(stringLiteral: event.title)
      let stop = AlarmButton(text: "إيقاف", textColor: .white, systemImageName: "stop.fill")
      let alert = AlarmPresentation.Alert(title: title, stopButton: stop)
      let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                                       metadata: Metadata(), tintColor: .green)
      _ = try await AlarmManager.shared.schedule(id: event.id,
        configuration: .alarm(schedule: .fixed(event.date), attributes: attributes))
    }
  #endif

  private func scheduleRefresh(ifNeeded: Bool) {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: refreshID)
    guard ifNeeded else { return }
    let refresh = BGAppRefreshTaskRequest(identifier: refreshID)
    refresh.earliestBeginDate = Date(timeIntervalSinceNow: 12 * 60 * 60)
    try? BGTaskScheduler.shared.submit(refresh)
  }

  private func backgroundRefresh(_ task: BGTask) {
    let previous = operation
    let refresh = Task {
      await previous?.value
      let plan = defaults.data(forKey: planKey)
        .flatMap { try? JSONDecoder().decode([ScheduledPrayer].self, from: $0) } ?? []
      scheduleRefresh(ifNeeded: plan.last.map { $0.date > Date() } ?? false)
      do {
        try Task.checkCancellation()
        try await apply(plan)
        task.setTaskCompleted(success: !Task.isCancelled)
      } catch {
        task.setTaskCompleted(success: false)
      }
    }
    operation = refresh
    task.expirationHandler = { refresh.cancel() }
  }
}
