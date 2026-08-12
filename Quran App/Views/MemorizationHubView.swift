import SwiftUI

/// The home of the memorization engine, pushed from the More tab. It pulls the
/// per-ayah spaced-repetition store and the per-surah heatmap store together:
/// one progress picture, a single Review-now entry point, and per-surah
/// management of goals and enrolled ayahs.
///
/// Ruled like the rest of the app — the percentage carries the page as a piece
/// of type rather than as a dial, and the surah list is hairline rows.
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
                progressSection
                reviewSection
                focusSection
                surahsSection

                if hasContent {
                    EditorialSection(title: "Everything", icon: "square.grid.3x3.fill",
                                     iconTint: Color(.label).opacity(0.4)) {
                        EditorialNavRow(title: "Full progress grid",
                                        caption: "All 114 surahs as a heat map") {
                            Haptics.tap()
                            showGrid = true
                        }
                        .padding(.bottom, 14)
                        EditorialNavRow(title: "How memorization works",
                                        caption: "Goals, reviews, and tracking — explained") {
                            Haptics.tap()
                            showGuide = true
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
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

    // MARK: - Progress

    private var progressSection: some View {
        let enrolled = srStore.totalCount
        let mature = srStore.matureCount
        let due = srStore.dueCount()
        let fraction = enrolled > 0 ? Double(mature) / Double(enrolled) : 0

        return EditorialSection(title: "Progress", icon: "chart.bar.fill", showsRule: false) {
            VStack(alignment: .leading, spacing: 0) {
                if enrolled == 0 {
                    // A 52pt em dash reads as a stray rule, not as "no data" —
                    // so the empty case says so in words instead.
                    Text("Nothing in review yet.")
                        .font(.appSerif(21, weight: .medium))
                        .padding(.bottom, 5)
                    Text("Ayahs you enrol from the reader are drilled here on a schedule.")
                        .font(.appSerif(15))
                        .foregroundStyle(Color(.label).opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.appSerif(52, weight: .medium))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                        Text("mastered")
                            .font(.appSerif(17, italic: true))
                            .foregroundStyle(Color(.label).opacity(0.45))
                    }
                    .padding(.bottom, 14)

                    RuleProgress(fraction: fraction, tint: .brand)

                    HStack(spacing: 18) {
                        StatDot(color: .orange, value: enrolled, label: "In review")
                        StatDot(color: .brand,  value: mature,   label: "Mastered")
                        StatDot(color: Color(.label).opacity(0.4), value: due, label: "Due")
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 14)
                }
            }
        }
    }

    // MARK: - Review

    @ViewBuilder
    private var reviewSection: some View {
        let due = srStore.dueCount()
        if due > 0 {
            EditorialSection(title: "Review", icon: "arrow.triangle.2.circlepath",
                             trailing: "\(due) due", trailingTint: .brand) {
                Text("\(due) ayah\(due == 1 ? "" : "s") ready to recall")
                    .font(.appSerif(17))
                    .foregroundStyle(Color(.label).opacity(0.72))
                    .padding(.bottom, 13)

                OutlineButton(label: "Start review", on: true) {
                    Haptics.tap()
                    session = ReviewSessionConfig(cards: srStore.dueItems(), title: "Review")
                }
            }
        } else if srStore.totalCount > 0 {
            EditorialSection(title: "Review", icon: "checkmark.circle.fill") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("All caught up")
                        .font(.appSerif(21, weight: .medium))
                    if let next = nextDueText {
                        Text(next)
                            .font(.appSerif(15, italic: true))
                            .foregroundStyle(Color(.label).opacity(0.45))
                    }
                }
            }
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

    // MARK: - Focus a single surah

    /// Lets the user drill one specific enrolled surah on demand — its due cards
    /// if any, otherwise all of them — without waiting for the global queue. Only
    /// shown once there are at least two surahs to choose between.
    @ViewBuilder
    private var focusSection: some View {
        let enrolled = srStore.enrolledSurahs()
        if enrolled.count >= 2 {
            let progress = srStore.surahProgress()
            EditorialSection(title: "Focus", icon: "scope") {
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
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Drill one surah")
                                .font(.appSerif(17))
                                .foregroundStyle(Color(.label))
                            Text("On its own, ahead of the queue")
                                .font(.appSerif(13.5, italic: true))
                                .foregroundStyle(Color(.label).opacity(0.45))
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(.label).opacity(0.3))
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Drill one surah")
            }
        }
    }

    /// Opens a review scoped to one surah: its due cards, or all of them when
    /// nothing is due so the surah can still be drilled.
    private func focusReview(surah: Int, name: String) {
        let due = srStore.dueItems(inSurah: surah)
        let all = srStore.cards(inSurah: surah)
        session = ReviewSessionConfig(cards: due.isEmpty ? all : due, title: name)
    }

    // MARK: - Your surahs

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
    private var surahsSection: some View {
        let tracked = trackedSurahs

        EditorialSection(title: "Your surahs", icon: "book.closed.fill",
                         trailing: tracked.isEmpty ? nil : "\(tracked.count)") {
            if tracked.isEmpty {
                HubEmptyState(onLearnMore: { showGuide = true })
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(tracked.enumerated()), id: \.element.id) { index, t in
                        if index > 0 {
                            Hairline(opacity: 0.6).padding(.vertical, 14)
                        }
                        NavigationLink {
                            SurahReviewDetailView(surahNumber: t.number, surah: surahByNumber[t.number])
                        } label: {
                            TrackedSurahRow(
                                tracked: t,
                                surah: surahByNumber[t.number],
                                goal: srStore.goal(forSurah: t.number) ?? .both
                            )
                        }
                        .buttonStyle(CardButtonStyle(scale: 0.985))
                    }
                }
            }
        }
    }
}

// MARK: - Tracked surah model

/// A surah shown in the hub list. It is either enrolled in spaced repetition
/// (`progress.enrolled > 0`, rendered with ayah-level progress) or only carries
/// a manual mark (rendered with its status instead).
private struct TrackedSurah: Identifiable {
    let number: Int
    let progress: SurahSRProgress
    let manualStatus: MemorizationStatus

    var id: Int { number }
    var isEnrolled: Bool { progress.enrolled > 0 }
}

// MARK: - Surah row

/// One ruled line per surah: the number in the margin, the name, and either the
/// ayah-level progress rule (enrolled) or the hand-set mark (not enrolled).
private struct TrackedSurahRow: View {
    let tracked: TrackedSurah
    let surah: Surah?
    let goal: MemorizationGoal

    private var fraction: Double {
        tracked.progress.enrolled > 0
            ? Double(tracked.progress.mature) / Double(tracked.progress.enrolled)
            : 0
    }

    private var subtitle: String {
        if tracked.isEnrolled {
            return "\(tracked.progress.mature)/\(tracked.progress.enrolled) mastered"
        }
        return tracked.manualStatus == .memorized
            ? "Marked memorized · not in review"
            : "Marked in progress · not in review"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(tracked.number)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .kerning(0.6)
                .foregroundStyle(.brand)
                .frame(minWidth: 22, alignment: .leading)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(surah?.englishName ?? "Surah \(tracked.number)")
                        .font(.appSerif(18, weight: .medium))
                        .foregroundStyle(Color(.label))
                    if tracked.isEnrolled {
                        MetaText(goal.shortTitle.uppercased(), tint: .brand, size: 8.5)
                    } else {
                        MetaText(tracked.manualStatus.label.uppercased(),
                                 tint: tracked.manualStatus.color, size: 8.5)
                    }
                    Spacer(minLength: 6)
                    if tracked.progress.due > 0 {
                        MetaText("\(tracked.progress.due) DUE", tint: .brand, size: 9)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(.label).opacity(0.3))
                }

                if tracked.isEnrolled {
                    RuleProgress(fraction: fraction, tint: .brand)
                        .padding(.top, 9)
                }

                Text(subtitle)
                    .font(.appSerif(13.5, italic: true))
                    .foregroundStyle(Color(.label).opacity(0.45))
                    .padding(.top, tracked.isEnrolled ? 8 : 2)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Empty state

private struct HubEmptyState: View {
    var onLearnMore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nothing in review yet.")
                .font(.appSerif(21, weight: .medium))
                .padding(.bottom, 5)
            Text("Pick a few ayahs and let spaced repetition do the remembering for you.")
                .font(.appSerif(15))
                .foregroundStyle(Color(.label).opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            EmptyStep(number: 1, text: "Open any surah from the Qur’an tab.")
            EmptyStep(number: 2, text: "Long-press an ayah and choose “Add to review”, or “Memorize this Surah” from the ⋯ menu.")
            EmptyStep(number: 3, text: "Come back here each day to review what’s due.")

            OutlineButton(label: "See how it works", action: onLearnMore)
                .padding(.top, 18)
        }
    }
}

/// A single numbered step in the onboarding empty state.
private struct EmptyStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(.brand)
                .frame(minWidth: 22, alignment: .leading)
                .padding(.top, 3)
            Text(text)
                .font(.appSerif(15))
                .foregroundStyle(Color(.label).opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number). \(text)")
    }
}

// MARK: - Goal badge

/// Kept for the reader's goal chooser, which still labels options inline.
struct GoalBadge: View {
    let goal: MemorizationGoal

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: goal.icon)
                .font(.system(size: 8, weight: .bold))
            Text(goal.shortTitle.uppercased())
                .font(.system(size: 8.5, weight: .semibold))
                .kerning(0.8)
        }
        .foregroundStyle(.brand)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .overlay(Rectangle().strokeBorder(Color.brand.opacity(0.4), lineWidth: 1))
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
    @State private var confirmRemoveSurah = false

    private var cards: [AyahReview] { srStore.cards(inSurah: surahNumber) }
    private var progress: SurahSRProgress { srStore.surahProgress()[surahNumber] ?? SurahSRProgress() }
    private var manualStatus: MemorizationStatus { memorizationStore.manualStatus(for: surahNumber) }

    private var goalBinding: Binding<MemorizationGoal> {
        Binding(
            get: { srStore.goal(forSurah: surahNumber) ?? .both },
            set: { srStore.setGoal($0, forSurah: surahNumber) }
        )
    }

    private var statusBinding: Binding<MemorizationStatus> {
        Binding(
            get: { memorizationStore.manualStatus(for: surahNumber) },
            set: { memorizationStore.set($0, for: surahNumber) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                // The goal only steers the review drills, so it's only meaningful
                // once at least one ayah is enrolled in spaced repetition.
                if !cards.isEmpty {
                    EditorialSection(title: "Goal", icon: "target") {
                        EditorialSegmented(
                            selection: goalBinding,
                            options: MemorizationGoal.allCases.map { .init($0, $0.shortTitle) }
                        )
                        Footnote(goalBinding.wrappedValue.caption + ". The review drills adapt to this.")
                    }
                }

                EditorialSection(title: "Your mark", icon: "hand.point.up.left.fill") {
                    EditorialSegmented(
                        selection: statusBinding,
                        options: [.init(MemorizationStatus.notStarted, "Not started"),
                                  .init(MemorizationStatus.inProgress, "In progress"),
                                  .init(MemorizationStatus.memorized, "Memorized")]
                    )
                    Footnote("Overrides the status by hand. Marking “Memorized” always counts as done.")
                }

                if !cards.isEmpty {
                    EditorialSection(title: "Enrolled ayahs", icon: "list.number",
                                     trailing: "\(cards.count)") {
                        OutlineButton(label: "Review this surah", icon: "play.fill", on: true) {
                            Haptics.tap()
                            let due = srStore.dueItems(inSurah: surahNumber)
                            session = ReviewSessionConfig(
                                cards: due.isEmpty ? cards : due,
                                title: surah?.englishName ?? "Review"
                            )
                        }
                        .padding(.bottom, 18)

                        VStack(spacing: 0) {
                            ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                                if index > 0 {
                                    Hairline(opacity: 0.6).padding(.vertical, 12)
                                }
                                AyahReviewRow(card: card)
                                    // The list is a ScrollView now, so removal moved
                                    // from a swipe to the long-press the rest of the
                                    // app already uses for ayah actions.
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            Haptics.warning()
                                            srStore.remove(surah: card.surah, ayah: card.ayah)
                                        } label: {
                                            Label("Remove from review", systemImage: "trash")
                                        }
                                    }
                            }
                        }

                        Footnote("Long-press an ayah to take it out of review.")

                        Button(role: .destructive) {
                            Haptics.warning()
                            confirmRemoveSurah = true
                        } label: {
                            Text("Remove surah from memorization")
                                .font(.appSerif(15))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 18)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle(surah?.englishName ?? "Surah \(surahNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $session) { cfg in
            ReviewSessionView(store: srStore, initialCards: cfg.cards, title: cfg.title)
        }
        .confirmationDialog("Remove this surah from memorization?",
                            isPresented: $confirmRemoveSurah, titleVisibility: .visible) {
            Button("Remove \(cards.count) ayah\(cards.count == 1 ? "" : "s")", role: .destructive) {
                srStore.removeSurah(surahNumber)
                dismiss()
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("Their review schedules are discarded. Your manual mark stays.")
        }
    }

    private var header: some View {
        let frac = progress.enrolled > 0 ? Double(progress.mature) / Double(progress.enrolled) : 0
        return VStack(alignment: .leading, spacing: 0) {
            if let surah {
                Text(surah.name)
                    .font(.appArabic(26))
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.bottom, 16)
            }

            if cards.isEmpty {
                // Manual-only surah: no ayah cards, so show the hand-set mark and
                // how to bring it into spaced-repetition review.
                HStack(spacing: 9) {
                    Image(systemName: manualStatus.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(manualStatus.color)
                    Text(manualStatus == .memorized
                         ? "Marked memorized. Enroll its ayahs from the reader to review them."
                         : "Marked in progress. Enroll its ayahs from the reader to start review.")
                        .font(.appSerif(15))
                        .foregroundStyle(Color(.label).opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                RuleProgress(fraction: frac, tint: .brand)
                HStack {
                    Text("\(progress.mature) of \(progress.enrolled) ayahs mastered")
                        .font(.appSerif(15))
                        .foregroundStyle(Color(.label).opacity(0.55))
                    Spacer()
                    if progress.due > 0 {
                        MetaText("\(progress.due) DUE", tint: .brand, size: 9.5)
                    }
                }
                .padding(.top, 12)
            }
        }
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
        HStack(alignment: .top, spacing: 14) {
            Text("\(card.ayah)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(card.isDue() ? .brand : Color(.label).opacity(0.35))
                .frame(minWidth: 22, alignment: .leading)
                .padding(.top, 6)

            VStack(alignment: .trailing, spacing: 7) {
                Text(card.arabic)
                    .font(.appArabic(19))
                    .lineLimit(1)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                HStack(spacing: 8) {
                    if card.isMature {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.brand)
                    }
                    MetaText(dueText.uppercased(),
                             tint: card.isDue() ? .brand : Color(.label).opacity(0.4),
                             size: 9)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
