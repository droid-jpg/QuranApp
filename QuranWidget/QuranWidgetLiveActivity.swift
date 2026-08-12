import ActivityKit
import WidgetKit
import SwiftUI

// NOTE: PrayerCountdownAttributes and AppTheme are defined in the main app
// target and pulled into this one through the "Quran App" folder membership
// exceptions in project.pbxproj.

/// The countdown to the next prayer, in the app's restyled language: small-caps
/// eyebrow, the prayer name in serif, and the user's chosen accent on the timer.
struct PrayerCountdownLiveActivity: Widget {
    private var accent: Color { AppTheme.current.accent }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerCountdownAttributes.self) { context in
            PrayerLiveActivityBanner(state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.prayerName, systemImage: prayerSymbol(context.state.prayerName))
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startTime...context.state.prayerTime, countsDown: true)
                        .font(.system(size: 19, weight: .semibold).monospacedDigit())
                        .foregroundStyle(accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("\(context.state.prayerName) prayer")
                            .font(.system(size: 13, design: .serif))
                        Spacer()
                        Text(context.state.prayerTime, style: .time)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: prayerSymbol(context.state.prayerName))
                    .foregroundStyle(accent)
            } compactTrailing: {
                Text(timerInterval: context.state.startTime...context.state.prayerTime, countsDown: true)
                    .foregroundStyle(accent).monospacedDigit()
            } minimal: {
                Image(systemName: prayerSymbol(context.state.prayerName))
                    .foregroundStyle(accent)
            }
        }
    }
}

private func prayerSymbol(_ name: String) -> String {
    switch name {
    case "Fajr":    return "moon.stars.fill"
    case "Dhuhr":   return "sun.max.fill"
    case "Asr":     return "sun.horizon.fill"
    case "Maghrib": return "sunset.fill"
    case "Isha":    return "moon.fill"
    default:        return "clock.fill"
    }
}

private struct PrayerLiveActivityBanner: View {
    let state: PrayerCountdownAttributes.ContentState
    private var accent: Color { AppTheme.current.accent }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: prayerSymbol(state.prayerName))
                .font(.system(size: 20))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("NEXT PRAYER")
                    .font(.system(size: 8.5, weight: .bold))
                    .kerning(1.3)
                    .foregroundStyle(.secondary)
                Text(state.prayerName)
                    .font(.system(size: 21, weight: .medium, design: .serif))
                Text(state.prayerTime, style: .time)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(timerInterval: state.startTime...state.prayerTime, countsDown: true)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(accent)
                    .multilineTextAlignment(.trailing)
                Text("REMAINING")
                    .font(.system(size: 8.5, weight: .bold))
                    .kerning(1.3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }
}
