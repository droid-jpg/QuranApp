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

    // MARK: - Daily memorization reminder

    /// A single daily nudge to keep the hifz habit going, at a user-chosen time and
    /// independent of prayer times. The body is personalized from the current
    /// memorization target (re-read each time this is called), so scheduling it at
    /// launch keeps it current.
    func scheduleMemorizationReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["memorization_daily"])

        let ud = UserDefaults.standard
        guard ud.bool(forKey: "memoReminderEnabled") else { return }

        let hour   = ud.object(forKey: "memoReminderHour")   as? Int ?? 19
        let minute = ud.object(forKey: "memoReminderMinute") as? Int ?? 0
        var comps = DateComponents(); comps.hour = hour; comps.minute = minute

        let content = UNMutableNotificationContent()
        content.title = "Time to memorize"
        if let data = UserDefaults(suiteName: sharedAppGroup)?.data(forKey: "quran_hifz_target_v1"),
           let t = try? JSONDecoder().decode(MemorizationTarget.self, from: data) {
            content.body = t.isComplete
                ? "Review \(t.surahName) with meaning flashcards to lock it in."
                : "Continue \(t.surahName) — ayah \(t.workingAyah). Keep your streak going."
        } else {
            content.body = "Pick an ayah and start memorizing. Small daily reps add up."
        }
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: "memorization_daily", content: content, trigger: trigger))
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
