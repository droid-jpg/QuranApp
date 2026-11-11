import SwiftUI

/// Memorization (REDESIGN §3.9), pushed from More and from Today's memorization row.
/// Top to bottom: Review (one section, one empty state), Practice for the ayah being
/// learned (three presets and "Mark ayah learned"), then every surah grouped by
/// status: Learning, Memorized, and Not started, collapsed.
///
/// Hosted inside a NavigationStack of its own host (More or Today); it has none.
/// It sends playback commands through the plain `audioServiceRef` and does not
/// observe the player.
struct MemorizationHubView: View {
    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @EnvironmentObject private var targetStore: MemorizationTargetStore
    @Environment(\.audioServiceRef) private var audioService

    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId

    /// The bundled surah list, so the groups never wait on the network.
    @State private var surahs = QuranOfflineStore.shared.surahs()
    @State private var session: ReviewSessionConfig?
    @State private var showGuide = false
    @State private var showNotStarted = false
    @State private var showSurahComplete = false

    private var surahByNumber: [Int: Surah] {
        Dictionary(uniqueKeysWithValues: surahs.map { ($0.number, $0) })
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.sectionGap) {
                reviewSection
                if let target = targetStore.target {
                    practiceSection(target)
                }
                statusGroups
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.top, Spacing.md)
            .padding(.bottom, Spacing.lg)
        }
        .background(Palette.background)
        .navigationTitle("Memorization")
        .navigationBarTitleDisplayMode(.inline)
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
        .task {
            if surahs.isEmpty {
                surahs = (try? await QuranAPIService.shared.fetchSurahList()) ?? []
            }
        }
        // Keep enrolled ayahs' cached translations in step with the user's
        // current translation choice: refresh on entry and on any later switch.
        .task(id: translationId) { await srStore.refreshTranslations() }
        .fullScreenCover(item: $session) { cfg in
            ReviewSessionView(store: srStore, initialCards: cfg.cards, title: cfg.title)
        }
        .sheet(isPresented: $showGuide) {
            MemorizationGuideView()
        }
        .confirmationDialog(
            "\(targetStore.target?.surahName ?? "Surah") memorized",
            isPresented: $showSurahComplete,
            titleVisibility: .visible
        ) {
            Button("Start meaning review") { enrollForMeaning() }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("Go back through it with meaning flashcards to lock in each ayah?")
        }
    }

    // MARK: - Review

    /// The one Review section, and the one empty state: "Nothing to review yet".
    @ViewBuilder
    private var reviewSection: some View {
        let enrolled = srStore.totalCount
        let due = srStore.dueCount()

        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Eyebrow("Review").accessibilityAddTraits(.isHeader)
                Spacer(minLength: Spacing.xs)
                if due > 0 {
                    MetaText("\(due) due", tint: Palette.accent)
                }
            }

            if enrolled == 0 {
                Text("Nothing to review yet")
                    .font(TypeScale.rowTitle)
                    .foregroundStyle(Palette.textPrimary)
                    .frame(minHeight: MinSize.surahRow, alignment: .leading)
            } else {
                if due > 0 {
                    Text("\(due) ayah\(due == 1 ? "" : "s") to review")
                        .font(TypeScale.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                    OutlineButton(label: "Start review", on: true) {
                        Haptics.tap()
                        session = ReviewSessionConfig(cards: srStore.dueItems(), title: "Review")
                    }
                } else {
                    Text("All caught up")
                        .font(TypeScale.rowTitle)
                        .foregroundStyle(Palette.textPrimary)
                    if let next = nextDueText {
                        Text(next)
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }

                let mature = srStore.matureCount
                RuleProgress(fraction: Double(mature) / Double(enrolled), tint: .brand)
                    .padding(.top, Spacing.xs)
                Text("\(mature) of \(enrolled) ayahs mastered")
                    .font(TypeScale.secondary)
                    .foregroundStyle(Palette.textSecondary)

                reviewOneSurah
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

    /// Review one enrolled surah on its own, ahead of the queue. Only offered once
    /// there are two or more surahs to choose between.
    @ViewBuilder
    private var reviewOneSurah: some View {
        let enrolled = srStore.enrolledSurahs()
        if enrolled.count >= 2 {
            let progress = srStore.surahProgress()
            Menu {
                ForEach(enrolled, id: \.self) { n in
                    let name = surahByNumber[n]?.englishName ?? "Surah \(n)"
                    let due = progress[n]?.due ?? 0
                    Button {
                        Haptics.tap()
                        reviewSurah(n, name: name)
                    } label: {
                        Text(due > 0 ? "\(name) · \(due) due" : name)
                    }
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    Text("Review one surah")
                        .font(TypeScale.body)
                        .foregroundStyle(Palette.accent)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(TypeScale.caption)
                        .foregroundStyle(Palette.textSecondary)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: MinSize.hitTarget)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Review one surah")
        }
    }

    /// A review scoped to one surah: its due cards, or all of them when nothing is due.
    private func reviewSurah(_ surah: Int, name: String) {
        let due = srStore.dueItems(inSurah: surah)
        let all = srStore.cards(inSurah: surah)
        session = ReviewSessionConfig(cards: due.isEmpty ? all : due, title: name)
    }

    // MARK: - Practice

    /// The ayah being learned, the three practice presets, and "Mark ayah learned".
    /// A preset only sets the repeat state and plays from it (`startRepeat`).
    private func practiceSection(_ t: MemorizationTarget) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Eyebrow("Practice").accessibilityAddTraits(.isHeader)

            Text(t.surahName)
                .font(TypeScale.rowTitle)
                .foregroundStyle(Palette.textPrimary)
            Text(t.isComplete ? "All \(t.totalAyahs) ayahs learned" : "Ayah \(t.workingAyah) of \(t.totalAyahs)")
                .font(TypeScale.secondary)
                .foregroundStyle(Palette.textSecondary)

            RuleProgress(fraction: t.fraction, tint: .brand)
                .padding(.vertical, Spacing.xxs)

            OutlineButton(label: "Repeat this ayah", icon: "repeat") {
                practice(.repeatThisAyah(surah: t.surah, ayah: t.workingAyah), t)
            }
            OutlineButton(label: "Listen, then recite", icon: "ear") {
                practice(.listenThenRecite(surah: t.surah, ayah: t.workingAyah), t)
            }
            OutlineButton(label: "Join with previous 2", icon: "link") {
                practice(.joinWithPrevious2(surah: t.surah, ayah: t.workingAyah), t)
            }
            if !t.isComplete {
                OutlineButton(label: "Mark ayah learned", icon: "checkmark.circle", on: true) {
                    markWorkingLearned()
                }
                .padding(.top, Spacing.xs)
            }
        }
    }

    private func practice(_ state: RepeatState, _ t: MemorizationTarget) {
        guard let audioService else { return }
        Haptics.tap()
        audioService.startRepeat(state, totalAyahs: t.totalAyahs, surahName: t.surahName)
    }

    /// Mark the working ayah learned and advance to the next. When the whole surah
    /// is done, the meaning-review offer (the method's last stage) is raised.
    private func markWorkingLearned() {
        targetStore.markWorkingAyahLearned()
        StreakService.shared.recordRead()
        Haptics.success()
        if targetStore.target?.isComplete == true {
            showSurahComplete = true
        }
    }

    /// Enroll every ayah of the finished surah in meaning-only review.
    private func enrollForMeaning() {
        guard let t = targetStore.target else { return }
        Task {
            guard let ayahs = try? await QuranAPIService.shared.fetchAyahs(surahNumber: t.surah) else { return }
            let seeds = ayahs.map {
                MemorizationSRStore.AyahSeed(
                    ayah: $0.numberInSurah, arabic: $0.arabic,
                    translation: $0.translation, transliteration: $0.transliteration
                )
            }
            srStore.enrollSurah(surah: t.surah, surahName: t.surahName, ayahs: seeds, goal: .meaning)
            memorizationStore.set(.memorized, for: t.surah)
            Haptics.success()
        }
    }

    // MARK: - Surahs by status

    private func surahs(with status: MemorizationStatus) -> [Surah] {
        surahs.filter { memorizationStore.status(for: $0.number) == status }
    }

    @ViewBuilder
    private var statusGroups: some View {
        let learning = surahs(with: .inProgress)
        let memorized = surahs(with: .memorized)
        let notStarted = surahs(with: .notStarted)

        if !learning.isEmpty {
            group("Learning", surahs: learning)
        }
        if !memorized.isEmpty {
            group("Memorized", surahs: memorized)
        }
        if !notStarted.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Button {
                    Haptics.selection()
                    withAnimation(Motion.standard) { showNotStarted.toggle() }
                } label: {
                    HStack(spacing: Spacing.xs) {
                        Eyebrow("Not started")
                        MetaText("\(notStarted.count)")
                        Spacer(minLength: 0)
                        Image(systemName: showNotStarted ? "chevron.up" : "chevron.down")
                            .font(TypeScale.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: MinSize.hitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityValue(showNotStarted ? "Expanded" : "Collapsed")

                if showNotStarted {
                    rows(notStarted)
                }
            }
        }
    }

    private func group(_ title: String, surahs: [Surah]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.xs) {
                Eyebrow(title)
                MetaText("\(surahs.count)")
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            rows(surahs)
        }
    }

    private func rows(_ list: [Surah]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.number) { index, s in
                if index > 0 { Hairline() }
                SurahStatusRow(surah: s, surahs: surahs,
                               onChange: { setStatus($0, for: s) },
                               onWorkOn: { workOn(s) })
            }
        }
    }

    // MARK: - Status changes

    /// Choosing Learning with nothing being learned yet makes that surah the one
    /// Practice works on; Not started or Memorized on the working surah clears it.
    private func setStatus(_ status: MemorizationStatus, for surah: Surah) {
        Haptics.selection()
        withAnimation(Motion.standard) {
            memorizationStore.set(status, for: surah.number)
            switch status {
            case .inProgress:
                if targetStore.target == nil {
                    targetStore.start(surah: surah.number, surahName: surah.englishName,
                                      totalAyahs: surah.numberOfAyahs)
                }
            case .notStarted, .memorized:
                if targetStore.target?.surah == surah.number { targetStore.clear() }
            }
        }
    }

    /// Make a Learning surah the one Practice works on.
    private func workOn(_ surah: Surah) {
        Haptics.tap()
        targetStore.start(surah: surah.number, surahName: surah.englishName,
                          totalAyahs: surah.numberOfAyahs)
    }
}

// MARK: - Surah row with a status control

/// The standard surah row shape (number, title and subtitle, Arabic name) with a
/// status menu where the play button would be: Not started, Learning, Memorized.
/// Tapping the text opens the surah's review page (Learning, Memorized) or the
/// reader (Not started).
private struct SurahStatusRow: View {
    let surah: Surah
    let surahs: [Surah]
    let onChange: (MemorizationStatus) -> Void
    let onWorkOn: () -> Void

    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @EnvironmentObject private var targetStore: MemorizationTargetStore
    @AppStorage("readingFace")  private var readingFace = ReadingFace.newYork.rawValue
    @AppStorage("arabicScript") private var arabicScript = ArabicScript.system.rawValue

    private var status: MemorizationStatus { memorizationStore.status(for: surah.number) }

    private var subtitle: String {
        let p = srStore.surahProgress()[surah.number]
        if let p, p.enrolled > 0 {
            let base = "\(p.mature)/\(p.enrolled) mastered"
            return p.due > 0 ? "\(base) · \(p.due) due" : base
        }
        if status == .inProgress, let t = targetStore.target, t.surah == surah.number {
            return "Ayah \(t.workingAyah) of \(t.totalAyahs)"
        }
        return "\(surah.englishNameTranslation) · \(surah.numberOfAyahs) ayahs"
    }

    var body: some View {
        HStack(spacing: 0) {
            NavigationLink {
                destination
            } label: {
                HStack(spacing: Spacing.sm) {
                    Text("\(surah.number)")
                        .font(TypeScale.secondary.monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(width: 28, alignment: .leading)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(surah.englishName)
                            .font(TypeScale.rowTitle)
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(TypeScale.secondary)
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(SurahRow.shortArabic(surah.name))
                        .font(TypeScale.arabicList)
                        .foregroundStyle(Palette.textPrimary)
                        .environment(\.layoutDirection, .rightToLeft)
                        .fixedSize()
                }
                .padding(.vertical, Spacing.xs)
                .frame(minHeight: MinSize.surahRow)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                ForEach([MemorizationStatus.notStarted, .inProgress, .memorized], id: \.self) { option in
                    Button {
                        onChange(option)
                    } label: {
                        if option == status {
                            Label(option.label, systemImage: "checkmark")
                        } else {
                            Text(option.label)
                        }
                    }
                }
                if status == .inProgress, targetStore.target?.surah != surah.number {
                    Divider()
                    Button("Practice this surah", action: onWorkOn)
                }
            } label: {
                Image(systemName: status.icon)
                    .font(TypeScale.heading)
                    .foregroundStyle(status == .notStarted ? Palette.textSecondary : Palette.accent)
                    .frame(width: MinSize.listPlayButton, height: MinSize.listPlayButton)
                    .contentShape(Rectangle())
            }
            .padding(.leading, Spacing.sm)
            .accessibilityLabel("\(surah.englishName) status")
            .accessibilityValue(status.label)
        }
    }

    @ViewBuilder
    private var destination: some View {
        if status == .notStarted, let idx = surahs.firstIndex(where: { $0.number == surah.number }) {
            SurahPageView(surahs: surahs, startIndex: idx)
        } else {
            SurahReviewDetailView(surahNumber: surah.number, surah: surah)
        }
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

                // The goal only steers the review modes, so it's only meaningful
                // once at least one ayah is enrolled in spaced repetition.
                if !cards.isEmpty {
                    EditorialSection(title: "Goal", icon: "target") {
                        EditorialSegmented(
                            selection: goalBinding,
                            options: MemorizationGoal.allCases.map { .init($0, $0.shortTitle) }
                        )
                    }
                }

                EditorialSection(title: "Your mark", icon: "hand.point.up.left.fill") {
                    EditorialSegmented(
                        selection: statusBinding,
                        options: [.init(MemorizationStatus.notStarted, "Not started"),
                                  .init(MemorizationStatus.inProgress, "Learning"),
                                  .init(MemorizationStatus.memorized, "Memorized")]
                    )
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
            Text("Their review schedules are discarded.")
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
                        .font(TypeScale.caption)
                        .foregroundStyle(manualStatus.color)
                    Text("\(manualStatus.label), not in review")
                        .font(.appSerif(15))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                RuleProgress(fraction: frac, tint: .brand)
                HStack {
                    Text("\(progress.mature) of \(progress.enrolled) ayahs mastered")
                        .font(.appSerif(15))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                    if progress.due > 0 {
                        MetaText("\(progress.due) due", tint: Palette.accent)
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
                .font(TypeScale.caption.monospacedDigit())
                .foregroundStyle(card.isDue() ? .brand : Color.secondary)
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
                            .font(TypeScale.caption)
                            .foregroundStyle(.brand)
                    }
                    MetaText(dueText, tint: card.isDue() ? Palette.accent : Palette.textSecondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
