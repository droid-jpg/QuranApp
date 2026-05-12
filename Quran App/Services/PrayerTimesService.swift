import Foundation
import CoreLocation
import Combine
import WidgetKit

@MainActor
class PrayerTimesService: NSObject, ObservableObject {
    @Published var prayerTimes: PrayerTimes?
    @Published var fetchStatus: FetchStatus = .notDetermined
    @Published var locationError: String?

    enum FetchStatus { case notDetermined, denied, fetching, ready }

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestAndFetch() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            fetchStatus = .fetching
            manager.requestLocation()
        default:
            fetchStatus = .denied
        }
    }

    func rescheduleNotifications() {
        guard let times = prayerTimes else { return }
        NotificationService.shared.scheduleIfEnabled(for: times)
        PrayerLiveActivityService.shared.scheduleAll(for: times)
    }

    private func fetchTimes(lat: Double, lon: Double) async {
        let urlStr = "https://api.aladhan.com/v1/timings?latitude=\(lat)&longitude=\(lon)&method=2"
        guard let url = URL(string: urlStr) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let dataObj = root["data"] as? [String: Any],
                let timings = dataObj["timings"] as? [String: String]
            else {
                locationError = "Unexpected prayer times format"
                return
            }

            let fajr    = parseTime(timings["Fajr"]    ?? "00:00")
            let maghrib = parseTime(timings["Maghrib"] ?? "00:00")

            // Islamic midnight = midpoint between Maghrib and *next* day's Fajr.
            // Since Fajr is earlier in the clock than Maghrib, next-day Fajr = Fajr + 24 h.
            let nextFajr = fajr.addingTimeInterval(86400)
            let islamicMidnight = maghrib.addingTimeInterval(nextFajr.timeIntervalSince(maghrib) / 2)

            let parsed = PrayerTimes(
                fajr:           fajr,
                sunrise:        parseTime(timings["Sunrise"] ?? "00:00"),
                dhuhr:          parseTime(timings["Dhuhr"]   ?? "00:00"),
                asr:            parseTime(timings["Asr"]     ?? "00:00"),
                maghrib:        maghrib,
                isha:           parseTime(timings["Isha"]    ?? "00:00"),
                islamicMidnight: islamicMidnight
            )
            prayerTimes = parsed
            fetchStatus = .ready
            NotificationService.shared.scheduleIfEnabled(for: parsed)
            PrayerLiveActivityService.shared.scheduleAll(for: parsed)
            // Share ALL times with widget — Sunrise and Midnight are included so the
            // widget can display the truly next upcoming event (not just canonical prayers).
            let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
            let prayerDict: [String: String] = [
                "Fajr":     timings["Fajr"]    ?? "",
                "Sunrise":  timings["Sunrise"] ?? "",
                "Dhuhr":    timings["Dhuhr"]   ?? "",
                "Asr":      timings["Asr"]     ?? "",
                "Maghrib":  timings["Maghrib"] ?? "",
                "Isha":     timings["Isha"]    ?? "",
                "Midnight": fmt.string(from: islamicMidnight)
            ]
            if let data = try? JSONEncoder().encode(prayerDict) {
                UserDefaults(suiteName: "group.sami.Quran-App")?.set(data, forKey: "prayerTimesDict")
            }
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            locationError = error.localizedDescription
            fetchStatus = .ready
        }
    }

    private func parseTime(_ str: String) -> Date {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return Date() }
        return Calendar.current.date(
            bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()
        ) ?? Date()
    }
}

extension PrayerTimesService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.first else { return }
        Task { @MainActor [weak self] in
            await self?.fetchTimes(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.locationError = error.localizedDescription
            self?.fetchStatus = .ready
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                self.fetchStatus = .fetching
                manager.requestLocation()
            case .denied, .restricted:
                self.fetchStatus = .denied
            default: break
            }
        }
    }
}

struct PrayerTimes {
    let fajr: Date
    let sunrise: Date
    let dhuhr: Date
    let asr: Date
    let maghrib: Date
    let isha: Date
    let islamicMidnight: Date

    /// Ordered for display — Sunrise sits after Fajr, Islamic Midnight after Isha.
    var named: [(name: String, time: Date)] {
        [
            ("Fajr",            fajr),
            ("Sunrise",         sunrise),
            ("Dhuhr",           dhuhr),
            ("Asr",             asr),
            ("Maghrib",         maghrib),
            ("Isha",            isha),
            ("Midnight",         islamicMidnight),
        ]
    }

    /// Only the five canonical prayers count as "next prayer" for highlighting.
    var nextPrayer: String {
        let now = Date()
        let prayers = [("Fajr", fajr), ("Dhuhr", dhuhr), ("Asr", asr), ("Maghrib", maghrib), ("Isha", isha)]
        for (name, date) in prayers where date > now { return name }
        return "Fajr"
    }
}
