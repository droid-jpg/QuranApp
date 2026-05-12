import ActivityKit
import Foundation

/// Shared between the main app target and the QuranWidget target.
/// After creating this file, you MUST also add it to the QuranWidget target:
/// In Xcode: select this file → File Inspector → Target Membership → check "QuranWidget".
struct PrayerCountdownAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var prayerName: String
        var prayerTime: Date
    }
    var prayerName: String
}
