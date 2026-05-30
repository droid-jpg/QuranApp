import ActivityKit
import WidgetKit
import SwiftUI

// NOTE: PrayerCountdownAttributes is defined in the main app target.
// This file is the widget-side rendering. The shared struct must be added
// to this target too via Xcode File Inspector → Target Membership → QuranWidget.

struct PrayerCountdownLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerCountdownAttributes.self) { context in
            PrayerLiveActivityBanner(state: context.state)
                .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.prayerName, systemImage: prayerSymbol(context.state.prayerName))
                        .font(.headline).foregroundStyle(.teal)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startTime...context.state.prayerTime, countsDown: true)
                        .font(.title3.monospacedDigit()).foregroundStyle(.teal)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("\(context.state.prayerName) prayer")
                        Spacer()
                        Text(context.state.prayerTime, style: .time)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: prayerSymbol(context.state.prayerName))
                    .foregroundStyle(.teal)
            } compactTrailing: {
                Text(timerInterval: context.state.startTime...context.state.prayerTime, countsDown: true)
                    .foregroundStyle(.teal).monospacedDigit()
            } minimal: {
                Image(systemName: prayerSymbol(context.state.prayerName))
                    .foregroundStyle(.teal)
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
}

private struct PrayerLiveActivityBanner: View {
    let state: PrayerCountdownAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: prayerSymbol(state.prayerName))
                .font(.title2).foregroundStyle(.teal)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(state.prayerName) Prayer")
                    .font(.headline)
                Text(state.prayerTime, style: .time)
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(timerInterval: state.startTime...state.prayerTime, countsDown: true)
                    .font(.title2.bold().monospacedDigit()).foregroundStyle(.teal)
                Text("remaining")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(16)
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
}
