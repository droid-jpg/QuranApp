import Foundation
import UserNotifications

class NotificationService {
    static let shared = NotificationService()
    private init() {}

    @discardableResult
    func requestPermission() async -> Bool {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    /// `denied`: refused earlier, so the system will not ask again (offer Settings).
    /// `declined`: refused just now, in the system alert (nothing more to say).
    enum Permission { case granted, denied, declined }

    /// Asks only when it has never been asked; answers from the stored choice
    /// otherwise. Call it when the user turns something on, never at launch.
    func ensurePermission() async -> Permission {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .notDetermined:
            return await requestPermission() ? .granted : .declined
        default:
            return .denied
        }
    }

    /// Replaces every pending prayer notification with one-off notifications at the
    /// real times of the coming days. (They used to repeat daily at the first day's
    /// clock times, which drifted as the days got longer or shorter.)
    func schedule(days: [PrayerTimes]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "notifEnabled") else { return }
        let preMinutes = defaults.object(forKey: "notifPreReminder") as? Int ?? 10
        let now = Date()

        var requests: [(date: Date, title: String, body: String)] = []
        for day in days {
            for (name, date) in day.named where defaults.object(forKey: "notif\(name)") as? Bool != false {
                let isPrayer = name != "Sunrise" && name != "Midnight"
                requests.append((date, isPrayer ? "\(name) Prayer" : name,
                                 isPrayer ? "Time for \(name) prayer" : "It's now \(name.lowercased())"))
                if preMinutes > 0 {
                    requests.append((date.addingTimeInterval(-Double(preMinutes) * 60),
                                     "\(name) in \(preMinutes) min",
                                     isPrayer ? "\(name) prayer begins in \(preMinutes) minutes"
                                              : "\(name) in \(preMinutes) minutes"))
                }
            }
        }

        // The system keeps at most 64 pending requests; the soonest ones win.
        for (index, request) in requests.filter({ $0.date > now }).sorted(by: { $0.date < $1.date }).prefix(60).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: request.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "prayer_\(index)", content: content, trigger: trigger))
        }
    }
}
