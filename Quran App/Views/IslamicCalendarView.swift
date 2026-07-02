import SwiftUI
import Combine

struct IslamicCalendarView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case month = "Month"
        case week  = "Week"
        case list  = "List"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .month
    @State private var selectedKind: IslamicEventKind? = nil
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var anchor = Date()          // month/week being browsed
    @State private var now = Date()

    private let cal = Calendar.current
    private let ticker = Timer.publish(every: 3600, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            kindFilterBar

            Divider()

            switch mode {
            case .month: monthScreen
            case .week:  weekScreen
            case .list:  AgendaList(kind: selectedKind, now: now)
            }
        }
        .navigationTitle("Islamic Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Kind filter

    private var kindFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                EventKindChip(label: "All", icon: "calendar", color: .brand,
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
    }

    // MARK: - Month

    private var monthScreen: some View {
        ScrollView {
            VStack(spacing: 0) {
                periodHeader(title: monthTitle,
                             onPrev: { shift(months: -1) },
                             onNext: { shift(months: 1) })

                weekdayHeader

                MonthGrid(days: monthGrid(),
                          anchorMonth: anchor,
                          selectedDay: selectedDay,
                          today: cal.startOfDay(for: now),
                          kind: selectedKind) { day in
                    select(day)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider().padding(.top, 4)

                DayEventsSection(day: selectedDay, kind: selectedKind, now: now)
            }
        }
    }

    // MARK: - Week

    private var weekScreen: some View {
        ScrollView {
            VStack(spacing: 0) {
                periodHeader(title: weekTitle,
                             onPrev: { shift(weeks: -1) },
                             onNext: { shift(weeks: 1) })

                weekdayHeader

                WeekStrip(days: weekGrid(),
                          selectedDay: selectedDay,
                          today: cal.startOfDay(for: now),
                          kind: selectedKind) { day in
                    select(day)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                Divider().padding(.top, 4)

                DayEventsSection(day: selectedDay, kind: selectedKind, now: now)
            }
        }
    }

    // MARK: - Shared chrome

    private func periodHeader(title: String, onPrev: @escaping () -> Void, onNext: @escaping () -> Void) -> some View {
        HStack {
            Button(action: onPrev) {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
            }
            Spacer()
            Text(title).font(.headline)
            Spacer()
            Button(action: onNext) {
                Image(systemName: "chevron.right").font(.body.weight(.semibold))
            }
        }
        .foregroundStyle(.brand)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .trailing) {
            if !cal.isDate(anchor, equalTo: now, toGranularity: mode == .week ? .weekOfYear : .month) {
                Button("Today") { jumpToToday() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.brand)
                    .padding(.trailing, 56)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Date helpers

    private var weekdaySymbols: [String] {
        let syms = cal.veryShortStandaloneWeekdaySymbols
        let shift = cal.firstWeekday - 1
        return Array(syms[shift...] + syms[..<shift])
    }

    private func monthGrid() -> [Date] {
        guard let monthInterval = cal.dateInterval(of: .month, for: anchor) else { return [] }
        let first = monthInterval.start
        let weekday = cal.component(.weekday, from: first)
        let lead = (weekday - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -lead, to: first) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func weekGrid() -> [Date] {
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: anchor) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekInterval.start) }
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: anchor)
    }

    private var weekTitle: String {
        guard let interval = cal.dateInterval(of: .weekOfYear, for: anchor),
              let last = cal.date(byAdding: .day, value: 6, to: interval.start) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let f2 = DateFormatter(); f2.dateFormat = "MMM d, yyyy"
        return "\(f.string(from: interval.start)) – \(f2.string(from: last))"
    }

    private func shift(months: Int = 0, weeks: Int = 0) {
        let comp = months != 0 ? DateComponents(month: months) : DateComponents(day: weeks * 7)
        if let d = cal.date(byAdding: comp, to: anchor) {
            withAnimation(.easeInOut(duration: 0.2)) { anchor = d }
        }
    }

    private func select(_ day: Date) {
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedDay = cal.startOfDay(for: day)
            if mode == .month, !cal.isDate(day, equalTo: anchor, toGranularity: .month) {
                anchor = day
            }
        }
    }

    private func jumpToToday() {
        withAnimation(.easeInOut(duration: 0.2)) {
            anchor = now
            selectedDay = cal.startOfDay(for: now)
        }
    }
}

// MARK: - Month grid

private struct MonthGrid: View {
    let days: [Date]
    let anchorMonth: Date
    let selectedDay: Date
    let today: Date
    let kind: IslamicEventKind?
    let onSelect: (Date) -> Void

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.timeIntervalSince1970) { day in
                CalendarDayCell(
                    day: day,
                    inMonth: cal.isDate(day, equalTo: anchorMonth, toGranularity: .month),
                    isToday: cal.isDate(day, inSameDayAs: today),
                    isSelected: cal.isDate(day, inSameDayAs: selectedDay),
                    dotColors: dotColors(for: day)
                )
                .onTapGesture { onSelect(day) }
            }
        }
    }

    private func dotColors(for day: Date) -> [Color] {
        IslamicEvent.events(on: day, kind: kind).prefix(3).map { $0.event.kind.color }
    }
}

// MARK: - Week strip

private struct WeekStrip: View {
    let days: [Date]
    let selectedDay: Date
    let today: Date
    let kind: IslamicEventKind?
    let onSelect: (Date) -> Void

    private let cal = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.timeIntervalSince1970) { day in
                CalendarDayCell(
                    day: day,
                    inMonth: true,
                    isToday: cal.isDate(day, inSameDayAs: today),
                    isSelected: cal.isDate(day, inSameDayAs: selectedDay),
                    dotColors: IslamicEvent.events(on: day, kind: kind).prefix(3).map { $0.event.kind.color },
                    tall: true
                )
                .onTapGesture { onSelect(day) }
            }
        }
    }
}

// MARK: - Day cell

private struct CalendarDayCell: View {
    let day: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let dotColors: [Color]
    var tall: Bool = false

    private let cal = Calendar.current

    var body: some View {
        VStack(spacing: 4) {
            Text("\(cal.component(.day, from: day))")
                .font(.system(size: 15, weight: isToday ? .bold : .regular))
                .foregroundStyle(numberColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(isSelected ? Color.brand : (isToday ? Color.brand.opacity(0.15) : .clear))
                )

            HStack(spacing: 3) {
                if dotColors.isEmpty {
                    Circle().fill(.clear).frame(width: 5, height: 5)
                } else {
                    ForEach(Array(dotColors.enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 5, height: 5)
                    }
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: tall ? 64 : 52)
        .contentShape(Rectangle())
        .opacity(inMonth ? 1 : 0.32)
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if isToday { return .brand }
        return .primary
    }
}

// MARK: - Selected-day events

private struct DayEventsSection: View {
    let day: Date
    let kind: IslamicEventKind?
    let now: Date

    private static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"; return f
    }()

    private var occurrences: [EventOccurrence] {
        IslamicEvent.events(on: day, kind: kind)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Self.fmt.string(from: day))
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.top, 14)

            if occurrences.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "calendar")
                            .font(.system(size: 28))
                            .foregroundStyle(.tertiary)
                        Text("No events on this day")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 28)
                    Spacer()
                }
            } else {
                ForEach(occurrences) { occ in
                    EventRow(occ: occ, now: now)
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 24)
    }
}

// MARK: - Agenda (list mode)

private struct AgendaList: View {
    let kind: IslamicEventKind?
    let now: Date

    private var occurrences: [EventOccurrence] {
        IslamicEvent.agenda(reference: now, pastWindowDays: 21, kind: kind)
    }

    var body: some View {
        if occurrences.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("No upcoming events")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(occurrences) { occ in
                EventRow(occ: occ, now: now)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            .listStyle(.plain)
        }
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
    let occ: EventOccurrence
    let now: Date

    @State private var expanded = false

    private var event: IslamicEvent { occ.event }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f
    }()
    private static let rangeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(event.kind.color.opacity(0.12))
                    Image(systemName: event.kind.icon)
                        .foregroundStyle(event.kind.color)
                        .font(.system(size: 16))
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.name).font(.body.bold())
                            Text(event.arabicName)
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                                .environment(\.layoutDirection, .rightToLeft)
                        }
                        Spacer()
                        Text(event.kind.label)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(event.kind.color.opacity(0.12))
                            .foregroundStyle(event.kind.color)
                            .clipShape(Capsule())
                    }

                    dateBlock
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } }

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
        let start = occ.start
        let end = occ.end
        let isActive = start <= now && now <= endOfDay(end)
        let isPast = endOfDay(end) < now

        HStack(spacing: 6) {
            Image(systemName: "calendar")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if occ.durationDays() > 1 {
                Text("\(Self.rangeFmt.string(from: start)) – \(Self.dayFmt.string(from: end))")
                    .font(.caption).foregroundStyle(.secondary)
                Text("· \(occ.durationDays()) days")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text(Self.dayFmt.string(from: start))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let note = event.recurrence.note {
                Text("· \(note)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Text("NOW")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(event.kind.color)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            } else if isPast {
                Text("Passed").font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text(countdown(to: start))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(event.kind.color)
            }
        }
    }

    private func endOfDay(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date)) ?? date
    }

    private func countdown(to date: Date) -> String {
        let secs = max(0, date.timeIntervalSince(now))
        let days = Int(secs) / 86400
        if days > 0 { return "in \(days)d" }
        let h = Int(secs) / 3600
        if h > 0 { return "in \(h)h" }
        return "today"
    }
}

#Preview {
    NavigationStack {
        IslamicCalendarView()
    }
}
