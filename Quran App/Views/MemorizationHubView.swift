import SwiftUI

/// The home of the memorization engine, pushed from the More tab. It pulls the
/// per-ayah spaced-repetition store and the per-surah heatmap store together:
/// one progress picture, a single Review-now entry point, and per-surah
/// management of goals and enrolled ayahs.
///
/// Hosted inside More's NavigationStack — it has no NavigationStack of its own.
struct MemorizationHubView: View {
    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @StateObject private var listVM = SurahListViewModel()

    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId

    @State private var session: ReviewSessionConfig?
    @State private var showGrid = false
    @State private var showGuide = false

    private var surahByNumber: [Int: Surah] {
        Dictionary(uniqueKeysWithValues: listVM.surahs.map { ($0.number, $0) })
    }

    /// Whether the user has anything in the system yet — drives the onboarding
    /// empty state vs. the populated hub.
    private var hasContent: Bool {
        srStore.totalCount > 0 || !memorizationStore.markedNumbers.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HubProgressHeader(
                    enrolled: srStore.totalCount,
                    mature: srStore.matureCount,
                    due: srStore.dueCount()
                )
                .padding(.horizontal, 16)

                if hasContent {
                    howItWorksLink
                        .padding(.horizontal, 16)
                }

                reviewCTA
                    .padding(.horizontal, 16)

                focusSurahPicker
                    .padding(.horizontal, 16)

                yourSurahsSection

                if hasContent {
                    gridButton
                        .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 18)
        }
        .navigationTitle("Memorization")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    showGuide = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("How memorization works")
            }
        }
        .task { await listVM.load() }
        // Keep enrolled ayahs' cached translations in step with the user's
        // current translation choice: refresh on entry and on any later switch.
        .task(id: translationId) { await srStore.refreshTranslations() }
        .fullScreenCover(item: $session) { cfg in
            ReviewSessionView(store: srStore, initialCards: cfg.cards, title: cfg.title)
        }
        .sheet(isPresented: $showGrid) {
            MemorizationOverviewSheet()
        }
        .sheet(isPresented: $showGuide) {
            MemorizationGuideView()
        }
    }

    // MARK: How-it-works link

    /// A standing entry to the full guide for users who already have ayahs in
    /// review (the onboarding empty state covers first-timers instead).
    private var howItWorksLink: some View {
        Button {
            Haptics.tap()
            showGuide = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.brand)
                VStack(alignment: .leading, spacing: 1) {
                    Text("How memorization works")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Goals, reviews, and tracking — explained")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .tintedCard(.brand)
        }
        .buttonStyle(.plain)
    }

    // MARK: Review call-to-action

    @ViewBuilder
    private var reviewCTA: some View {
        let due = srStore.dueCount()
        if due > 0 {
            Button {
                Haptics.tap()
                session = ReviewSessionConfig(cards: srStore.dueItems(), title: "Review")
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Review \(due) ayah\(due == 1 ? "" : "s")")
                            .font(.headline)
                        Text("Due now · spaced repetition")
                            .font(.caption)
                            .opacity(0.9)
                    }
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 24))
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(Color.brand)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        } else if srStore.totalCount > 0 {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.brand)
                VStack(alignment: .leading, spacing: 2) {
                    Text("All caught up")
                        .font(.subheadline.bold())
                    if let next = nextDueText {
                        Text(next)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(16)
            .tintedCard(.brand)
        }
    }

    private var nextDueText: String? {
        guard let soonest = srStore.cards.values.map(\.dueDate).min() else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: soonest)).day ?? 0
        if days <= 0 { return "Next review ready soon" }
        if days == 1 { return "Next review tomorrow" }
        return "Next review in \(days) days"
    }

    // MARK: Focus a single surah

    /// Lets the user drill one specific enrolled surah on demand — its due cards
    /// if any, otherwise all of them — without waiting for the global queue. Only
    /// shown once there are at least two surahs to choose between.
    @ViewBuilder
    private var focusSurahPicker: some View {
        let enrolled = srStore.enrolledSurahs()
        if enrolled.count >= 2 {
            let progress = srStore.surahProgress()
            Menu {
                ForEach(enrolled, id: \.self) { n in
                    let name = surahByNumber[n]?.englishName ?? "Surah \(n)"
                    let due = progress[n]?.due ?? 0
                    Button {
                        Haptics.tap()
                        focusReview(surah: n, name: name)
                    } label: {
                        Text(due > 0 ? "\(name) · \(due) due" : name)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "scope")
                        .foregroundStyle(.brand)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Focus on one surah")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Drill a single surah on its own")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    /// Opens a review scoped to one surah: its due cards, or all of them when
    /// nothing is due so the surah can still be drilled.
    private func focusReview(surah: Int, name: String) {
        let due = srStore.dueItems(inSurah: surah)
        let all = srStore.cards(inSurah: surah)
        session = ReviewSessionConfig(cards: due.isEmpty ? all : due, title: name)
    }

    // MARK: Your surahs

    /// The hub's surah list = every surah with ayahs enrolled in spaced
    /// repetition, unioned with the surahs the user marked by hand. Sorted by
    /// surah number so the picture is predictable.
    private var trackedSurahs: [TrackedSurah] {
        let progress = srStore.surahProgress()
        let numbers = Set(srStore.enrolledSurahs()).union(memorizationStore.markedNumbers)
        return numbers.sorted().map { n in
            TrackedSurah(
                number: n,
                progress: progress[n] ?? SurahSRProgress(),
                manualStatus: memorizationStore.manualStatus(for: n)
            )
        }
    }

    @ViewBuilder
    private var yourSurahsSection: some View {
        let tracked = trackedSurahs

        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                SectionHeader(title: "Your Surahs", systemImage: "book.closed.fill", tint: .brand)
                if !tracked.isEmpty {
                    Text("Tap a surah to set its goal, mark your progress, or review its ayahs.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)

            if tracked.isEmpty {
                HubEmptyState(onLearnMore: { showGuide = true })
                    .padding(.horizontal, 16)
            } else {
                VStack(spacing: 10) {
                    ForEach(tracked) { t in
                        NavigationLink {
                            SurahReviewDetailView(surahNumber: t.number, surah: surahByNumber[t.number])
                        } label: {
                            if t.isEnrolled {
                                EnrolledSurahRow(
                                    surahNumber: t.number,
                                    surah: surahByNumber[t.number],
                                    goal: srStore.goal(forSurah: t.number) ?? .both,
                                    progress: t.progress
                                )
                            } else {
                                MarkedSurahRow(
                                    surahNumber: t.number,
                                    surah: surahByNumber[t.number],
                                    status: t.manualStatus
                                )
                            }
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var gridButton: some View {
        Button {
            Haptics.tap()
            showGrid = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.3x3.fill")
                    .foregroundStyle(.brand)
                Text("Full progress grid")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress header (ring + stats)

private struct HubProgressHeader: View {
    let enrolled: Int
    let mature: Int
    let due: Int

    private var fraction: Double { enrolled > 0 ? Double(mature) / Double(enrolled) : 0 }
    private var percent: Int { Int((fraction * 100).rounded()) }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .stroke(Color(.tertiarySystemFill), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: max(0.0001, fraction))
                    .stroke(
                        LinearGradient(colors: [.brand, .brand.opacity(0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: fraction)
                VStack(spacing: 2) {
                    Text(enrolled == 0 ? "—" : "\(percent)%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("mastered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 140)

            HStack(spacing: 0) {
                StatPill(value: enrolled, label: "In Review", color: .orange)
                Divider().frame(height: 36)
                StatPill(value: mature, label: "Mastered", color: .green)
                Divider().frame(height: 36)
                StatPill(value: due, label: "Due Now", color: .brand)
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Tracked surah model

/// A surah shown in the hub list. It is either enrolled in spaced repetition
/// (`progress.enrolled > 0`, rendered with ayah-level progress) or only carries
/// a manual mark (rendered as a status pill).
private struct TrackedSurah: Identifiable {
    let number: Int
    let progress: SurahSRProgress
    let manualStatus: MemorizationStatus

    var id: Int { number }
    var isEnrolled: Bool { progress.enrolled > 0 }
}

// MARK: - Enrolled surah row

private struct EnrolledSurahRow: View {
    let surahNumber: Int
    let surah: Surah?
    let goal: MemorizationGoal
    let progress: SurahSRProgress

    private var fraction: Double {
        progress.enrolled > 0 ? Double(progress.mature) / Double(progress.enrolled) : 0
    }

    var body: some View {
        HStack(spacing: 14) {
            NumberBadge(number: surahNumber)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(surah?.englishName ?? "Surah \(surahNumber)")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.primary)
                    GoalBadge(goal: goal)
                }

                // Mini progress bar (mature within enrolled)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(Color.green)
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                }
                .frame(height: 5)

                Text("\(progress.mature)/\(progress.enrolled) mastered")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            if progress.due > 0 {
                Text("\(progress.due) due")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.brand, in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Goal badge

struct GoalBadge: View {
    let goal: MemorizationGoal

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: goal.icon)
            Text(goal.shortTitle)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.brand)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.brand.opacity(0.12), in: Capsule())
    }
}

// MARK: - Marked surah row (manual mark, no ayahs in review)

/// A surah the user marked by hand but hasn't enrolled in spaced repetition.
/// There are no ayah cards to show progress for, so it surfaces the manual
/// status and a nudge toward adding it to review. Tapping opens the same detail
/// as an enrolled surah.
private struct MarkedSurahRow: View {
    let surahNumber: Int
    let surah: Surah?
    let status: MemorizationStatus

    private var subtitle: String {
        status == .memorized ? "Marked memorized · not in review"
                             : "Marked in progress · not in review"
    }

    var body: some View {
        HStack(spacing: 14) {
            NumberBadge(number: surahNumber)

            VStack(alignment: .leading, spacing: 4) {
                Text(surah?.englishName ?? "Surah \(surahNumber)")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)

            StatusPill(status: status)

            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))
        )
    }
}

/// Compact pill mirroring a `MemorizationStatus` (its icon, label, and colour).
private struct StatusPill: View {
    let status: MemorizationStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.icon)
            Text(status.label)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(status.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Empty state

private struct HubEmptyState: View {
    var onLearnMore: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(colors: [.brand, .brand.opacity(0.6)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                Text("Start memorizing")
                    .font(.headline)
                Text("Pick a few ayahs and let spaced repetition do the remembering for you.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 14) {
                EmptyStep(number: 1, icon: "book.fill",
                          text: "Open any surah from the Quran tab.")
                EmptyStep(number: 2, icon: "plus.circle.fill",
                          text: "Tap + on an ayah, or “Memorize Surah” from the ⋯ menu.")
                EmptyStep(number: 3, icon: "graduationcap.fill",
                          text: "Come back here each day to review what's due.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onLearnMore) {
                Text("See how it works")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground))
        )
    }
}

/// A single numbered step in the onboarding empty state.
private struct EmptyStep: View {
    let number: Int
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.brand.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(.brand)
            }
            .frame(width: 30, height: 30)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}

// MARK: - Per-surah review detail

/// Manage one surah's memorization: its goal, manual status, the enrolled ayahs,
/// and a scoped review session. Pushed from the hub.
struct SurahReviewDetailView: View {
    let surahNumber: Int
    let surah: Surah?

    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @Environment(\.dismiss) private var dismiss

    @State private var session: ReviewSessionConfig?

    private var cards: [AyahReview] { srStore.cards(inSurah: surahNumber) }
    private var progress: SurahSRProgress { srStore.surahProgress()[surahNumber] ?? SurahSRProgress() }
    private var manualStatus: MemorizationStatus { memorizationStore.manualStatus(for: surahNumber) }

    private var goalBinding: Binding<MemorizationGoal> {
        Binding(
            get: { srStore.goal(forSurah: surahNumber) ?? .both },
            set: { Haptics.selection(); srStore.setGoal($0, forSurah: surahNumber) }
        )
    }

    private var statusBinding: Binding<MemorizationStatus> {
        Binding(
            get: { memorizationStore.manualStatus(for: surahNumber) },
            set: { Haptics.selection(); memorizationStore.set($0, for: surahNumber) }
        )
    }

    var body: some View {
        List {
            Section {
                progressHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }

            // The goal only steers the review drills, so it's only meaningful
            // once at least one ayah is enrolled in spaced repetition.
            if !cards.isEmpty {
                Section {
                    Picker("Goal", selection: goalBinding) {
                        ForEach(MemorizationGoal.allCases) { g in
                            Label(g.title, systemImage: g.icon).tag(g)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Label("Goal", systemImage: "target")
                } footer: {
                    Text(goalBinding.wrappedValue.caption + ". The review drills adapt to this.")
                }
            }

            Section {
                Picker("Status", selection: statusBinding) {
                    Label("Not Started", systemImage: "circle").tag(MemorizationStatus.notStarted)
                    Label("In Progress", systemImage: "circle.dotted.and.circle").tag(MemorizationStatus.inProgress)
                    Label("Memorized", systemImage: "checkmark.circle.fill").tag(MemorizationStatus.memorized)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Label("Your Mark", systemImage: "hand.point.up.left")
            } footer: {
                Text("Override the status manually. Marking “Memorized” always counts as done.")
            }

            Section {
                Button {
                    Haptics.tap()
                    let due = srStore.dueItems(inSurah: surahNumber)
                    session = ReviewSessionConfig(
                        cards: due.isEmpty ? cards : due,
                        title: surah?.englishName ?? "Review"
                    )
                } label: {
                    Label("Review this surah", systemImage: "play.fill")
                }
                .disabled(cards.isEmpty)
            }

            if !cards.isEmpty {
                Section {
                    ForEach(cards) { card in
                        AyahReviewRow(card: card)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Haptics.warning()
                                    srStore.remove(surah: card.surah, ayah: card.ayah)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                } header: {
                    Text("\(cards.count) Enrolled Ayah\(cards.count == 1 ? "" : "s")")
                }

                Section {
                    Button(role: .destructive) {
                        Haptics.warning()
                        srStore.removeSurah(surahNumber)
                        dismiss()
                    } label: {
                        Label("Remove surah from memorization", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(surah?.englishName ?? "Surah \(surahNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $session) { cfg in
            ReviewSessionView(store: srStore, initialCards: cfg.cards, title: cfg.title)
        }
    }

    private var progressHeader: some View {
        let frac = progress.enrolled > 0 ? Double(progress.mature) / Double(progress.enrolled) : 0
        return VStack(alignment: .leading, spacing: 10) {
            if let surah {
                Text(surah.name)
                    .font(.system(size: 24))
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if cards.isEmpty {
                // Manual-only surah: no ayah cards, so show the hand-set mark and
                // how to bring it into spaced-repetition review.
                HStack(spacing: 8) {
                    Image(systemName: manualStatus.icon)
                        .foregroundStyle(manualStatus.color)
                    Text(manualStatus == .memorized
                         ? "Marked memorized. Enroll its ayahs from the reader to review them."
                         : "Marked in progress. Enroll its ayahs from the reader to start review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.tertiarySystemFill))
                        Capsule().fill(Color.green).frame(width: max(0, geo.size.width * frac))
                    }
                }
                .frame(height: 6)
                HStack {
                    Text("\(progress.mature) of \(progress.enrolled) ayahs mastered")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if progress.due > 0 {
                        Text("\(progress.due) due")
                            .font(.caption.bold())
                            .foregroundStyle(.brand)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct AyahReviewRow: View {
    let card: AyahReview

    private var dueText: String {
        if card.isDue() { return "Due now" }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: card.dueDate)).day ?? 0
        if days <= 1 { return "Due tomorrow" }
        return "Due in \(days) days"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("\(card.ayah)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.brand)
                .frame(width: 30, height: 30)
                .background(Color.brand.opacity(0.12), in: Circle())

            Text(card.arabic)
                .font(.system(size: 17))
                .lineLimit(1)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .trailing, spacing: 2) {
                Text(dueText)
                    .font(.caption2)
                    .foregroundStyle(card.isDue() ? .brand : .secondary)
                if card.isMature {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
