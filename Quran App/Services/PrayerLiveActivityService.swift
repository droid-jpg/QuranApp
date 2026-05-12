import ActivityKit
import Foundation

/// Manages the prayer-countdown Live Activity.
/// Started 10 minutes before each canonical prayer, dismissed when prayer time arrives.
@MainActor
final class PrayerLiveActivityService {
    static let shared = PrayerLiveActivityService()
    private var pendingTimers: [Timer] = []
    private init() {}

    func scheduleAll(for times: PrayerTimes) {
        cancelTimers()
        guard UserDefaults.standard.bool(forKey: "liveActivityEnabled") else {
            Task { await endAll() }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let prayers: [(String, Date)] = [
            ("Fajr",    times.fajr),
            ("Dhuhr",   times.dhuhr),
            ("Asr",     times.asr),
            ("Maghrib", times.maghrib),
            ("Isha",    times.isha),
        ]
        let now = Date()
        for (name, prayerDate) in prayers {
            let launchAt = prayerDate.addingTimeInterval(-10 * 60)
            if launchAt <= now && prayerDate > now {
                // Already in the 10-minute window — start immediately.
                Task { await start(name: name, time: prayerDate) }
            } else if launchAt > now {
                let delay = launchAt.timeIntervalSince(now)
                let t = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.start(name: name, time: prayerDate)
                    }
                }
                pendingTimers.append(t)
            }
        }
    }

    private func start(name: String, time: Date) async {
        await endAll()
        let attrs   = PrayerCountdownAttributes(prayerName: name)
        let state   = PrayerCountdownAttributes.ContentState(prayerName: name, prayerTime: time)
        let content = ActivityContent(state: state, staleDate: time.addingTimeInterval(60))
        do {
            _ = try Activity<PrayerCountdownAttributes>.request(
                attributes: attrs, content: content, pushType: nil)
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    private func endAll() async {
        for activity in Activity<PrayerCountdownAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func cancelTimers() {
        pendingTimers.forEach { $0.invalidate() }
        pendingTimers.removeAll()
    }
}
