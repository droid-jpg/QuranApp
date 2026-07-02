import Foundation

/// A prayer-time calculation method, mapped to the Aladhan API's `method` id. The
/// method sets the Fajr/Isha twilight angles, which differ by region and authority,
/// so letting the user choose is essential for accurate local times.
struct PrayerCalcMethod: Identifiable, Hashable {
    let id: Int        // Aladhan `method` parameter
    let name: String

    static let all: [PrayerCalcMethod] = [
        PrayerCalcMethod(id: 3,  name: "Muslim World League"),
        PrayerCalcMethod(id: 2,  name: "ISNA (North America)"),
        PrayerCalcMethod(id: 5,  name: "Egyptian General Authority"),
        PrayerCalcMethod(id: 4,  name: "Umm al-Qura (Makkah)"),
        PrayerCalcMethod(id: 1,  name: "University of Karachi"),
        PrayerCalcMethod(id: 7,  name: "Tehran, Geophysics"),
        PrayerCalcMethod(id: 8,  name: "Gulf Region"),
        PrayerCalcMethod(id: 9,  name: "Kuwait"),
        PrayerCalcMethod(id: 10, name: "Qatar"),
        PrayerCalcMethod(id: 11, name: "Singapore"),
        PrayerCalcMethod(id: 13, name: "Diyanet (Turkey)"),
        PrayerCalcMethod(id: 15, name: "Moonsighting Committee"),
    ]

    static func name(for id: Int) -> String {
        all.first { $0.id == id }?.name ?? "ISNA (North America)"
    }

    // MARK: Stored preferences (read by PrayerTimesService and Settings)

    static let methodKey = "prayerCalcMethod"
    static let schoolKey = "prayerAsrSchool"   // 0 = Standard (Shafi'i), 1 = Hanafi

    static var selectedMethodId: Int {
        UserDefaults.standard.object(forKey: methodKey) as? Int ?? 2
    }
    static var selectedSchool: Int {
        UserDefaults.standard.object(forKey: schoolKey) as? Int ?? 0
    }
}
