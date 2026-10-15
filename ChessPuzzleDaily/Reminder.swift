import Foundation
import UserNotifications

/// Daily "puzzle of the day" reminder at 19:00 local time — port of Reminder.kt. Android re-arms
/// an AlarmManager alarm and renders the notification itself at fire time (so it can skip a day
/// that's already solved); iOS instead hands the OS a single repeating
/// `UNCalendarNotificationTrigger`, which the system re-evaluates every day on its own — there's
/// no app code running at delivery time to check "already solved today", so that one Android-side
/// skip doesn't carry over here. Title/body are baked in at scheduling time and refreshed whenever
/// `apply`/`schedule` runs again (e.g. after a language change).
enum Reminder {
    static let hour = 19
    private static let identifier = "daily_puzzle"

    /// Call whenever the user's notify preference (or language) may have changed, and once at
    /// app launch. Requests permission only when the user actually wants the reminder on; iOS
    /// caches the permission decision, so repeat calls after the first don't re-prompt.
    static func apply(store: ProgressStore) {
        guard store.notify else { cancel(); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { schedule(store: store) }
        }
    }

    static func schedule(store: ProgressStore) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard store.notify else { return }
        let s = stringsFor(store.lang ?? .ru)
        let content = UNMutableNotificationContent()
        content.title = s.notifTitle
        content.body = s.notifText
        content.sound = .default
        var when = DateComponents()
        when.hour = hour
        when.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: true)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
