import SwiftUI

/// Memorization overview presented as a sheet from the Quran tab:
/// juz-scoped progress, stats, and the 114-surah heat-map grid.
struct MemorizationOverviewSheet: View {
    @EnvironmentObject private var store: MemorizationStore
    @EnvironmentObject private var srStore: MemorizationSRStore
    @StateObject private var listVM = SurahListViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var selectedJuz: Int? = nil   // nil = all juz

    // Surahs visible in the current juz scope
    private var juzSurahs: [Surah] {
        guard let juz = selectedJuz else { return listVM.surahs }
        let nums = Set(JuzData.surahNumbers(inJuz: juz))
        return listVM.surahs.filter { nums.contains($0.number) }
    }

    /// Effective per-surah status, blending the manual mark with review progress.
    private var effectiveStatuses: [Int: MemorizationStatus] {
        let prog = srStore.surahProgress()
        var out: [Int: MemorizationStatus] = [:]
        for s in listVM.surahs {
            let p = prog[s.number] ?? SurahSRProgress()
            out[s.number] = store.effectiveStatus(
                for: s.number, enrolled: p.enrolled, mature: p.mature, totalAyahs: s.numberOfAyahs
            )
        }
        return out
    }

    var body: some View {
        let statuses = effectiveStatuses
        NavigationStack {
            VStack(spacing: 0) {
                MemorizationProgressBar(
                    surahs: juzSurahs,
                    statuses: statuses,
                    selectedJuz: selectedJuz
                )

                MemorizationStatsBar(surahs: juzSurahs, statuses: statuses)

                JuzPicker(selectedJuz: $selectedJuz)

                if listVM.isLoading {
                    ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    MemorizationGrid(surahs: juzSurahs, statuses: statuses)
                }
            }
            .navigationTitle(selectedJuz.map { "Juz \($0)" } ?? "Memorization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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

// MARK: - Progress bar

struct MemorizationProgressBar: View {
    let surahs: [Surah]
    let statuses: [Int: MemorizationStatus]
    let selectedJuz: Int?

    private func status(_ n: Int) -> MemorizationStatus { statuses[n] ?? .notStarted }

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
                if status(s.number) == .memorized  { memorizedAyahs  += n }
                if status(s.number) == .inProgress { inProgressAyahs += n }
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
            let mem = surahs.filter { status($0.number) == .memorized  }.count
            let inp = surahs.filter { status($0.number) == .inProgress }.count
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
    let statuses: [Int: MemorizationStatus]

    private func status(_ n: Int) -> MemorizationStatus { statuses[n] ?? .notStarted }
    private var memorizedCount: Int  { surahs.filter { status($0.number) == .memorized  }.count }
    private var inProgressCount: Int { surahs.filter { status($0.number) == .inProgress }.count }
    private var remainingCount: Int  { surahs.count - memorizedCount - inProgressCount }

    var body: some View {
        HStack(spacing: 0) {
            StatPill(value: memorizedCount,  label: "Memorized",  color: .green)
            Divider().frame(height: 36)
            StatPill(value: inProgressCount, label: "In Progress", color: .orange)
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
                .contentTransition(.numericText())
                .animation(AppAnim.spring, value: value)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Grid

struct MemorizationGrid: View {
    let surahs: [Surah]
    let statuses: [Int: MemorizationStatus]

    /// Discrete zoom stops (column counts). Fewer columns → larger cells that have
    /// room to show the surah name alongside its number.
    private static let stops = [10, 8, 6, 4, 3]
    @State private var columnCount = 10

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount)
    }
    private var showNames: Bool { columnCount <= 6 }

    private func zoom(_ magnification: Double) {
        guard let i = Self.stops.firstIndex(of: columnCount) else { return }
        let ni: Int
        if magnification > 1.1       { ni = min(Self.stops.count - 1, i + 1) }  // pinch out → fewer cols
        else if magnification < 0.9  { ni = max(0, i - 1) }                     // pinch in → more cols
        else { return }
        guard ni != i else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            columnCount = Self.stops[ni]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    GridLegend(color: .green,                     label: "Memorized")
                    GridLegend(color: .orange,                    label: "In Progress")
                    GridLegend(color: Color(.tertiarySystemFill), label: "Not started")
                }
                .padding(.horizontal)
                .padding(.top, 10)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right.magnifyingglass")
                    Text("Pinch to zoom")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal)

                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(surahs.indices, id: \.self) { idx in
                        let surah = surahs[idx]
                        NavigationLink(destination: SurahPageView(surahs: surahs, startIndex: idx)) {
                            GridCell(
                                number: surah.number,
                                name: surah.englishName,
                                showName: showNames,
                                status: statuses[surah.number] ?? .notStarted
                            )
                        }
                        .buttonStyle(CardButtonStyle(scale: 0.88))
                        .hapticTap()
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 16)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: columnCount)
            }
        }
        .gesture(
            MagnifyGesture().onEnded { zoom($0.magnification) }
        )
    }
}

struct GridCell: View {
    let number: Int
    var name: String? = nil
    var showName: Bool = false
    let status: MemorizationStatus

    private var fill: Color {
        switch status {
        case .notStarted: return Color(.systemFill)
        case .inProgress: return .orange
        case .memorized:  return .green
        }
    }

    private var textColor: Color {
        switch status {
        case .notStarted: return .secondary
        case .inProgress, .memorized: return .white
        }
    }

    private var corner: CGFloat { showName ? 8 : 5 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner)
                .fill(fill)
                .animation(AppAnim.spring, value: status)
            if showName, let name {
                VStack(spacing: 1) {
                    Text("\(number)")
                        .font(.system(size: 12, weight: .bold))
                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 3)
                }
                .foregroundStyle(textColor)
                .animation(AppAnim.smooth, value: status)
            } else {
                Text("\(number)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(textColor)
                    .animation(AppAnim.smooth, value: status)
            }
        }
        .frame(height: showName ? 50 : 34)
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

