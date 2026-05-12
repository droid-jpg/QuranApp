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

    func scheduleIfEnabled(for times: PrayerTimes) {
        let center = UNUserNotificationCenter.current()

        // Remove ALL possible prayer + event notification IDs so stale ones never linger.
        // "Islamic Midnight" and "IslamicMidnight" cover old IDs from previous app versions.
        let allPossibleNames = [
            "Fajr", "Sunrise", "Dhuhr", "Asr", "Maghrib", "Isha",
            "Midnight", "Islamic Midnight", "IslamicMidnight"
        ]
        let allIds = allPossibleNames.flatMap { ["prayer_\($0)_at", "prayer_\($0)_pre"] }
        center.removePendingNotificationRequests(withIdentifiers: allIds)

        guard UserDefaults.standard.bool(forKey: "notifEnabled") else { return }

        let preMin = UserDefaults.standard.object(forKey: "notifPreReminder") as? Int ?? 10

        // Informational entries — friendlier copy, no "Prayer" suffix
        let infoNames: Set<String> = ["Sunrise", "Midnight"]

        for (name, date) in times.named {
            guard UserDefaults.standard.object(forKey: "notif\(name)") as? Bool != false else { continue }

            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)

            if infoNames.contains(name) {
                // At-time notification
                let atBody = name == "Sunrise" ? "It's now sunrise" : "It's now midnight"
                addDaily(id: "prayer_\(name)_at",
                         title: name,
                         body: atBody,
                         comps: comps)

                // Pre-reminder notification
                if preMin > 0 {
                    let earlier = date.addingTimeInterval(-Double(preMin) * 60)
                    let preComps = Calendar.current.dateComponents([.hour, .minute], from: earlier)
                    let preBody = name == "Sunrise"
                        ? "Sunrise in \(preMin) minutes"
                        : "Midnight in \(preMin) minutes"
                    addDaily(id: "prayer_\(name)_pre",
                             title: "\(name) in \(preMin) min",
                             body: preBody,
                             comps: preComps)
                }
            } else {
                // Canonical prayer
                addDaily(id: "prayer_\(name)_at",
                         title: "\(name) Prayer",
                         body: "Time for \(name) prayer",
                         comps: comps)

                if preMin > 0 {
                    let earlier = date.addingTimeInterval(-Double(preMin) * 60)
                    let preComps = Calendar.current.dateComponents([.hour, .minute], from: earlier)
                    addDaily(id: "prayer_\(name)_pre",
                             title: "\(name) in \(preMin) min",
                             body: "\(name) prayer begins in \(preMin) minutes",
                             comps: preComps)
                }
            }
        }
    }

    private func addDaily(id: String, title: String, body: String, comps: DateComponents) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        )
    }
}

enum PrayerName: String, CaseIterable {
    case fajr = "Fajr", dhuhr = "Dhuhr", asr = "Asr", maghrib = "Maghrib", isha = "Isha"
}
