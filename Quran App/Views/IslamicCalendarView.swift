import SwiftUI
import Combine

/// The Islamic calendar, ruled. The grid keeps its shape — a month is a grid —
/// but selection is a square mark rather than a filled circle, the day numerals
/// are set in the reading serif, and every event is a ruled entry instead of a
/// tinted card.
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
            VStack(spacing: 14) {
                EditorialSegmented(
                    selection: $mode,
                    options: Mode.allCases.map { .init($0, $0.rawValue) }
                )
                kindFilterBar
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 14)

            Hairline()

            switch mode {
            case .month: monthScreen
            case .week:  weekScreen
            case .list:  AgendaList(kind: selectedKind, now: now)
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(ticker) { now = $0 }
    }

    // MARK: - Kind filter

    private var kindFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            .padding(.vertical, 1)
        }
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
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

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
                .padding(.horizontal, 20)
                .padding(.bottom, 14)

                DayEventsSection(day: selectedDay, kind: selectedKind, now: now)
            }
        }
    }

    // MARK: - Shared chrome

    private func periodHeader(title: String, onPrev: @escaping () -> Void, onNext: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(action: onPrev) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.brand)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Previous")

            Text(title)
                .font(.appSerif(20, weight: .medium))
                .frame(maxWidth: .infinity)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.brand)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            if !cal.isDate(anchor, equalTo: now, toGranularity: mode == .week ? .weekOfYear : .month) {
                Button("TODAY") { jumpToToday() }
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1.2)
                    .foregroundStyle(.brand)
                    .offset(y: 12)
            }
        }
        .padding(.bottom, 14)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, s in
                Text(s.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.8)
                    .foregroundStyle(Color(.label).opacity(0.35))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
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
        Haptics.selection()
        let comp = months != 0 ? DateComponents(month: months) : DateComponents(day: weeks * 7)
        if let d = cal.date(byAdding: comp, to: anchor) {
            withAnimation(.easeInOut(duration: 0.2)) { anchor = d }
        }
    }

    private func select(_ day: Date) {
        Haptics.selection()
        withAnimation(.easeInOut(duration: 0.15)) {
            selectedDay = cal.startOfDay(for: day)
            if mode == .month, !cal.isDate(day, equalTo: anchor, toGranularity: .month) {
                anchor = day
            }
        }
    }

    private func jumpToToday() {
        Haptics.tap()
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
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
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
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
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
        VStack(spacing: 5) {
            Text("\(cal.component(.day, from: day))")
                .font(.appSerif(16, weight: isToday || isSelected ? .semibold : .regular))
                .foregroundStyle(numberColor)
                .frame(width: 32, height: 32)
                .background {
                    if isSelected {
                        Rectangle().fill(Color.brand)
                    } else if isToday {
                        Rectangle().strokeBorder(Color.brand, lineWidth: 1)
                    }
                }

            // Event marks — small squares, since nothing else on the page is a dot.
            HStack(spacing: 3) {
                if dotColors.isEmpty {
                    Rectangle().fill(.clear).frame(width: 4, height: 4)
                } else {
                    ForEach(Array(dotColors.enumerated()), id: \.offset) { _, c in
                        Rectangle().fill(c).frame(width: 4, height: 4)
                    }
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
        .frame(height: tall ? 64 : 54)
        .contentShape(Rectangle())
        .opacity(inMonth ? 1 : 0.28)
    }

    private var numberColor: Color {
        if isSelected { return Color(.systemBackground) }
        if isToday { return .brand }
        return Color(.label)
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
        VStack(alignment: .leading, spacing: 0) {
            Hairline().padding(.bottom, 15)
            Eyebrow(Self.fmt.string(from: day))
                .padding(.bottom, occurrences.isEmpty ? 0 : 16)

            if occurrences.isEmpty {
                Text("Nothing marked on this day.")
                    .font(.appSerif(16, italic: true))
                    .foregroundStyle(Color(.label).opacity(0.4))
                    .padding(.top, 14)
            } else {
                ForEach(Array(occurrences.enumerated()), id: \.element.id) { index, occ in
                    if index > 0 { Hairline(opacity: 0.6).padding(.vertical, 16) }
                    EventRow(occ: occ, now: now)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.bottom, 34)
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
            EditorialEmptyState(
                icon: "calendar",
                title: "Nothing upcoming.",
                message: "No events match this filter in the months ahead."
            )
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(occurrences.enumerated()), id: \.element.id) { index, occ in
                        if index > 0 { Hairline(opacity: 0.6).padding(.vertical, 16) }
                        EventRow(occ: occ, now: now)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
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
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(isSelected ? color : Color(.label).opacity(0.4))
                Text(label.uppercased())
                    .font(.system(size: 9.5, weight: .semibold))
                    .kerning(1)
                    .foregroundStyle(isSelected ? color : Color(.label).opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(
                Rectangle().strokeBorder(isSelected ? color : Color(.label).opacity(0.18), lineWidth: 1)
            )
            .contentShape(Rectangle())
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
                Image(systemName: event.kind.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(event.kind.color)
                    .frame(width: 20)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(event.name)
                            .font(.appSerif(18, weight: .medium))
                            .foregroundStyle(Color(.label))
                        Spacer(minLength: 6)
                        MetaText(event.kind.label.uppercased(), tint: event.kind.color, size: 8.5)
                    }

                    Text(event.arabicName)
                        .font(.appArabic(15))
                        .foregroundStyle(Color(.label).opacity(0.45))
                        .environment(\.layoutDirection, .rightToLeft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 3)

                    dateBlock
                        .padding(.top, 9)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.tap()
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            }

            if expanded {
                Text(event.description)
                    .font(.appSerif(15))
                    .foregroundStyle(Color(.label).opacity(0.6))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .padding(.leading, 32)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var dateBlock: some View {
        let start = occ.start
        let end = occ.end
        let isActive = start <= now && now <= endOfDay(end)
        let isPast = endOfDay(end) < now

        HStack(spacing: 7) {
            if occ.durationDays() > 1 {
                MetaText("\(Self.rangeFmt.string(from: start)) – \(Self.dayFmt.string(from: end))", size: 9.5)
                MetaText("· \(occ.durationDays()) DAYS", tint: Color(.label).opacity(0.32), size: 9)
            } else {
                MetaText(Self.dayFmt.string(from: start), size: 9.5)
            }

            if let note = event.recurrence.note {
                MetaText("· \(note.uppercased())", tint: Color(.label).opacity(0.32), size: 9)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isActive {
                Text("NOW")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(event.kind.color)
            } else if isPast {
                MetaText("PASSED", tint: Color(.label).opacity(0.3), size: 9)
            } else {
                MetaText(countdown(to: start).uppercased(), tint: event.kind.color, size: 9.5)
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
