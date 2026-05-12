import SwiftUI

struct PrayerTimesCardView: View {
    @ObservedObject var service: PrayerTimesService

    var body: some View {
        switch service.fetchStatus {
        case .notDetermined:
            Button {
                service.requestAndFetch()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.circle.fill")
                        .foregroundStyle(.teal)
                    Text("Enable Prayer Times")
                        .font(.subheadline)
                        .foregroundStyle(.teal)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

        case .denied:
            HStack(spacing: 8) {
                Image(systemName: "location.slash.fill")
                    .foregroundStyle(.secondary)
                Text("Location access denied — enable in Settings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

        case .fetching:
            HStack(spacing: 8) {
                ProgressView()
                Text("Getting prayer times…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

        case .ready:
            if let times = service.prayerTimes {
                PrayerTimesRow(times: times)
            }
        }
    }
}

private struct PrayerTimesRow: View {
    let times: PrayerTimes

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    // Names that are informational, not canonical prayers
    private static let infoEntries: Set<String> = ["Sunrise", "Midnight"]

    var body: some View {
        let next = times.nextPrayer
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(times.named, id: \.name) { entry in
                    let isNext  = entry.name == next
                    let isInfo  = Self.infoEntries.contains(entry.name)
                    VStack(spacing: 4) {
                        Text(entry.name)
                            .font(.caption2.bold())
                            .foregroundStyle(
                                isNext ? .white :
                                isInfo ? Color.orange.opacity(0.85) :
                                        .secondary
                            )
                        Text(Self.fmt.string(from: entry.time))
                            .font(.subheadline.bold())
                            .foregroundStyle(isNext ? .white : .primary)
                        if isNext {
                            Text("Next")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                isNext ? Color.teal :
                                isInfo ? Color.orange.opacity(0.08) :
                                        Color(.tertiarySystemBackground)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isNext ? Color.clear :
                                isInfo ? Color.orange.opacity(0.25) :
                                        Color(.separator).opacity(0.4),
                                lineWidth: 0.5
                            )
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}
