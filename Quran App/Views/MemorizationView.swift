import SwiftUI

struct MemorizationView: View {
    @EnvironmentObject private var store: MemorizationStore
    @StateObject private var listVM = SurahListViewModel()

    @State private var filter: FilterMode = .all
    @State private var isGrid = false
    @State private var selectedJuz: Int? = nil   // nil = all juz

    enum FilterMode: String, CaseIterable {
        case all = "All"
        case inProgress = "In Progress"
        case memorized = "Memorized"
        case review = "Review"
    }

    // Surahs visible in the current juz scope
    private var juzSurahs: [Surah] {
        guard let juz = selectedJuz else { return listVM.surahs }
        let nums = Set(JuzData.surahNumbers(inJuz: juz))
        return listVM.surahs.filter { nums.contains($0.number) }
    }

    // juzSurahs filtered further by status filter (list mode)
    private var displayed: [Surah] {
        switch filter {
        case .all:        return juzSurahs
        case .inProgress: return juzSurahs.filter { store.status(for: $0.number) == .inProgress }
        case .memorized:  return juzSurahs.filter { store.status(for: $0.number) == .memorized }
        case .review:     return juzSurahs.filter { store.isReviewed($0.number) }
        }
    }

    private var scopedInProgressNumbers: [Int] {
        juzSurahs.filter { store.status(for: $0.number) == .inProgress }.map(\.number)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MemorizationProgressBar(
                    surahs: juzSurahs,
                    store: store,
                    selectedJuz: selectedJuz
                )

                MemorizationStatsBar(surahs: juzSurahs, store: store)

                JuzPicker(selectedJuz: $selectedJuz)

                if !isGrid && !scopedInProgressNumbers.isEmpty {
                    InProgressScroller(
                        numbers: scopedInProgressNumbers,
                        surahs: listVM.surahs
                    )
                }

                if !isGrid {
                    Picker("Filter", selection: $filter) {
                        ForEach(FilterMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    Divider()
                }

                if listVM.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isGrid {
                    MemorizationGrid(surahs: juzSurahs, store: store)
                } else {
                    List(displayed) { surah in
                        MemorizationRow(
                            surah: surah,
                            status: store.status(for: surah.number),
                            isReviewed: store.isReviewed(surah.number),
                            onCycle: { store.cycle(for: surah.number) },
                            onToggleReview: { store.toggleReview(surah.number) }
                        )
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(selectedJuz.map { "Juz \($0)" } ?? "Memorization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) { isGrid.toggle() }
                    } label: {
                        Image(systemName: isGrid ? "list.bullet" : "grid.circle")
                    }
                }
            }
            .task { await listVM.load() }
        }
    }
}

// MARK: - Juz picker

struct JuzPicker: View {
    @Binding var selectedJuz: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                JuzChip(label: "All", isSelected: selectedJuz == nil) {
                    selectedJuz = nil
                }
                ForEach(1...30, id: \.self) { n in
                    JuzChip(label: "\(n)", isSelected: selectedJuz == n) {
                        selectedJuz = n
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }
}

struct JuzChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(isSelected ? Color.teal : Color(.tertiarySystemBackground)))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Progress bar

struct MemorizationProgressBar: View {
    let surahs: [Surah]
    @ObservedObject var store: MemorizationStore
    let selectedJuz: Int?

    private struct Progress {
        let memorizedFraction: Double
        let inProgressFraction: Double
        let label: String
    }

    private var progress: Progress {
        if let juz = selectedJuz {
            // Ayah-accurate progress within the juz
            var totalAyahs = 0
            var memorizedAyahs = 0
            var inProgressAyahs = 0
            for s in surahs {
                let n = JuzData.ayahsInJuz(surahNumber: s.number, surahTotalAyahs: s.numberOfAyahs, juz: juz)
                totalAyahs += n
                if store.status(for: s.number) == .memorized  { memorizedAyahs  += n }
                if store.status(for: s.number) == .inProgress { inProgressAyahs += n }
            }
            let t = totalAyahs > 0 ? Double(totalAyahs) : 1
            let pct = Int(Double(memorizedAyahs) / t * 100)
            let label = "\(pct)% of Juz \(juz) memorized · \(memorizedAyahs)/\(totalAyahs) ayahs"
            return Progress(
                memorizedFraction: Double(memorizedAyahs) / t,
                inProgressFraction: Double(inProgressAyahs) / t,
                label: label
            )
        } else {
            // Surah-count-based overall progress
            let mem = surahs.filter { store.status(for: $0.number) == .memorized  }.count
            let inp = surahs.filter { store.status(for: $0.number) == .inProgress }.count
            let total = Double(surahs.count > 0 ? surahs.count : 114)
            let pct = Int(Double(mem) / total * 100)
            return Progress(
                memorizedFraction: Double(mem) / total,
                inProgressFraction: Double(inp) / total,
                label: "\(pct)% memorized · \(mem)/114 surahs complete"
            )
        }
    }

    var body: some View {
        let p = progress
        VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle().fill(Color.green)
                        .frame(width: geo.size.width * p.memorizedFraction)
                    Rectangle().fill(Color.orange)
                        .frame(width: geo.size.width * p.inProgressFraction)
                    Rectangle().fill(Color(.tertiarySystemFill))
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            .padding(.horizontal)

            Text(p.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Stats bar

struct MemorizationStatsBar: View {
    let surahs: [Surah]
    @ObservedObject var store: MemorizationStore

    private var memorizedCount: Int  { surahs.filter { store.status(for: $0.number) == .memorized  }.count }
    private var inProgressCount: Int { surahs.filter { store.status(for: $0.number) == .inProgress }.count }
    private var reviewedCount: Int   { surahs.filter { store.isReviewed($0.number) }.count }
    private var remainingCount: Int  { surahs.count - memorizedCount - inProgressCount }

    var body: some View {
        HStack(spacing: 0) {
            StatPill(value: memorizedCount,  label: "Memorized",  color: .green)
            Divider().frame(height: 36)
            StatPill(value: inProgressCount, label: "In Progress", color: .orange)
            Divider().frame(height: 36)
            StatPill(value: reviewedCount,   label: "Review",      color: .yellow)
            Divider().frame(height: 36)
            StatPill(value: remainingCount,  label: "Remaining",   color: .secondary)
        }
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
    }
}

struct StatPill: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - In-progress cards

struct InProgressScroller: View {
    let numbers: [Int]
    let surahs: [Surah]

    private func surah(for n: Int) -> Surah? { surahs.first { $0.number == n } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(numbers, id: \.self) { n in
                    if let s = surah(for: n) {
                        NavigationLink(destination: SurahDetailView(surah: s)) {
                            HStack(spacing: 10) {
                                Image(systemName: "play.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(s.englishName)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text("In Progress · \(s.numberOfAyahs) ayahs")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                                Spacer(minLength: 8)
                                Text(s.name)
                                    .font(.system(size: 18))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(width: 240)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Grid

struct MemorizationGrid: View {
    let surahs: [Surah]
    @ObservedObject var store: MemorizationStore

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 10)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    GridLegend(color: .green,                                label: "Memorized")
                    GridLegend(color: .orange,                               label: "In Progress")
                    GridLegend(color: Color(.tertiarySystemFill), border: .yellow, label: "Review")
                    GridLegend(color: Color(.tertiarySystemFill),            label: "Not started")
                }
                .padding(.horizontal)
                .padding(.top, 10)

                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(surahs) { surah in
                        NavigationLink(destination: SurahDetailView(surah: surah)) {
                            GridCell(
                                number: surah.number,
                                status: store.status(for: surah.number),
                                isReviewed: store.isReviewed(surah.number)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
            }
        }
    }
}

struct GridCell: View {
    let number: Int
    let status: MemorizationStatus
    let isReviewed: Bool

    private var fill: Color {
        switch status {
        case .notStarted: return Color(.tertiarySystemFill)
        case .inProgress: return .orange.opacity(0.75)
        case .memorized:  return .green.opacity(0.75)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .overlay(
                    Group {
                        if isReviewed {
                            RoundedRectangle(cornerRadius: 4).stroke(Color.yellow, lineWidth: 2)
                        }
                    }
                )
            Text("\(number)")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(status == .notStarted ? Color.secondary : .white)
        }
        .frame(height: 32)
    }
}

struct GridLegend: View {
    let color: Color
    var border: Color? = nil
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .overlay(
                    Group {
                        if let b = border { RoundedRectangle(cornerRadius: 2).stroke(b, lineWidth: 1.5) }
                    }
                )
                .frame(width: 12, height: 12)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Memorization row

struct MemorizationRow: View {
    let surah: Surah
    let status: MemorizationStatus
    let isReviewed: Bool
    let onCycle: () -> Void
    let onToggleReview: () -> Void

    var body: some View {
        NavigationLink(destination: SurahDetailView(surah: surah)) {
            HStack(spacing: 14) {
                Button(action: onCycle) {
                    Image(systemName: status.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(status.color)
                        .frame(width: 30)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(surah.englishName)
                            .font(.system(.body, weight: .medium))
                        if isReviewed {
                            Image(systemName: "bookmark.fill")
                                .font(.caption2)
                                .foregroundStyle(.yellow)
                        }
                    }
                    Text(surah.englishNameTranslation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(surah.name)
                    .font(.system(size: 18))
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { withAnimation { onCycle() } } label: {
                Label(status.next.label, systemImage: status.next.icon)
            }
            .tint(status.next.color)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button { withAnimation { onToggleReview() } } label: {
                Label(
                    isReviewed ? "Remove Review" : "Mark Review",
                    systemImage: isReviewed ? "bookmark.slash" : "bookmark"
                )
            }
            .tint(.yellow)
        }
    }
}
