import SwiftUI
import Combine

struct IslamicCalendarView: View {
    @State private var selectedKind: IslamicEventKind? = nil
    @State private var now = Date()

    private let ticker = Timer.publish(every: 3600, on: .main, in: .common).autoconnect()

    private var filtered: [IslamicEvent] {
        let events = selectedKind == nil
            ? IslamicEvent.all
            : IslamicEvent.all.filter { $0.kind == selectedKind }
        // Sort: upcoming first, then past (by date), then recurring at end
        return events.sorted { a, b in
            let aDate = a.actualDate
            let bDate = b.actualDate
            switch (aDate, bDate) {
            case (nil, nil):   return a.id < b.id
            case (nil, _):     return false   // recurring goes last
            case (_, nil):     return true
            case (let d1?, let d2?): return d1 < d2
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Kind filter bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    EventKindChip(label: "All", icon: "calendar", color: .teal,
                                  isSelected: selectedKind == nil) { selectedKind = nil }
                    ForEach([IslamicEventKind.holiday, .fastingMonth, .fastingDay, .recommended],
                            id: \.rawValue) { kind in
                        EventKindChip(label: kind.label, icon: kind.icon, color: kind.color,
                                      isSelected: selectedKind == kind) {
                            selectedKind = selectedKind == kind ? nil : kind
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(Color(.secondarySystemBackground))

            List(filtered) { event in
                EventRow(event: event, now: now)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listStyle(.plain)
        }
        .navigationTitle("Islamic Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { now = $0 }
    }
}

// MARK: - Filter chip

private struct EventKindChip: View {
    let label: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? color.opacity(0.15) : Color(.tertiarySystemBackground))
                .foregroundStyle(isSelected ? color : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? color : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Event row

private struct EventRow: View {
    let event: IslamicEvent
    let now: Date

    @State private var expanded = false

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private static let rangeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top, spacing: 12) {
                // Kind icon tile
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(event.kind.color.opacity(0.12))
                    Image(systemName: event.kind.icon)
                        .foregroundStyle(event.kind.color)
                        .font(.system(size: 16))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    // Name + kind badge
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.name)
                                .font(.body.bold())
                            Text(event.arabicName)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                        Spacer()
                        Text(event.kind.label)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(event.kind.color.opacity(0.12))
                            .foregroundStyle(event.kind.color)
                            .clipShape(Capsule())
                    }

                    // Date / countdown row
                    dateBlock
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }

            // Expandable description
            if expanded {
                Text(event.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(event.kind.color.opacity(0.2), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var dateBlock: some View {
        if let start = event.actualDate {
            let isPast = (event.actualEndDate ?? start) < now
            let isActive = start <= now && now <= (event.actualEndDate ?? start)

            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Date range string
                if let end = event.actualEndDate, event.durationDays > 1 {
                    Text("\(Self.rangeFmt.string(from: start)) – \(Self.dayFmt.string(from: end))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(Self.dayFmt.string(from: start))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if event.durationDays > 1 {
                    Text("· \(event.durationDays) days")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Status badge
                if isActive {
                    Text("NOW")
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(event.kind.color)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                } else if isPast {
                    Text("Passed")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(countdown(to: start))
                        .font(.caption.monospacedDigit())
                        .fontWeight(.semibold)
                        .foregroundStyle(event.kind.color)
                }
            }
        } else {
            // Recurring event
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
                Text("Recurring — no fixed yearly date")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }

    private func countdown(to date: Date) -> String {
        let secs = max(0, date.timeIntervalSince(now))
        let days = Int(secs) / 86400
        if days > 0 { return "in \(days)d" }
        let h = Int(secs) / 3600
        if h > 0 { return "in \(h)h" }
        return "soon"
    }
}

#Preview {
    NavigationStack {
        IslamicCalendarView()
    }
}
