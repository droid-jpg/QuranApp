import SwiftUI

/// How the reader sets its type. A plain value, so an ayah row can tell cheaply
/// whether anything it draws has changed.
struct ReaderStyle: Equatable {
    var arabicSize: Double
    var translationSize: Double
    var transliterationSize: Double
    var showTranslation: Bool
    var showTransliteration: Bool
    var face: String
    var script: String

    var serif: ReadingFace { ReadingFace(rawValue: face) ?? .newYork }
    var arabic: ArabicScript {
        let stored = ArabicScript(rawValue: script) ?? .system
        return stored.isAvailable ? stored : .system
    }
}

// MARK: - Reader

struct ReaderView: View {
    let surah: Surah
    var startAyah: Int? = nil

    @Environment(Player.self) private var player
    @Environment(AppRouter.self) private var router
    @Environment(Downloads.self) private var downloads
    @EnvironmentObject private var bookmarks: BookmarkStore

    @AppStorage("arabicFontSize") private var arabicFontSize: Double = 26
    @AppStorage("translationFontSize") private var translationFontSize: Double = 17
    @AppStorage("transliterationFontSize") private var transliterationFontSize: Double = 13
    @AppStorage("showTranslation") private var showTranslation = true
    @AppStorage("showTransliteration") private var showTransliteration = true
    @AppStorage("readingFace") private var readingFace = ReadingFace.newYork.rawValue
    @AppStorage("arabicScript") private var arabicScript = ArabicScript.system.rawValue
    @AppStorage("selectedTranslationId") private var translationId = Translation.fallbackId

    @State private var ayahs: [Ayah]
    /// Choosing the ayahs to repeat: waiting for the first, or for the last.
    @State private var picking: Picking?
    @State private var selected: Ayah?
    @State private var showType = false
    @State private var showGoTo = false
    @State private var goToText = ""
    /// When the reader was last scrolled by hand. A reference, so noting it doesn't redraw.
    @State private var touch = TouchClock()

    enum Picking: Equatable {
        case first
        case last(first: Int)
    }

    final class TouchClock { var last = Date.distantPast }

    init(surah: Surah, startAyah: Int? = nil, startPicking: Bool = false) {
        self.surah = surah
        self.startAyah = startAyah
        _ayahs = State(initialValue: QuranText.shared.ayahs(surah.number))
        _picking = State(initialValue: startPicking ? .first : nil)
    }

    private var style: ReaderStyle {
        ReaderStyle(arabicSize: arabicFontSize, translationSize: translationFontSize,
                    transliterationSize: transliterationFontSize, showTranslation: showTranslation,
                    showTransliteration: showTransliteration, face: readingFace, script: arabicScript)
    }

    private var isCurrentSurah: Bool { player.isCurrent(surah.number) }

    var body: some View {
        let current = isCurrentSurah ? player.ayah : 0
        let range = isCurrentSurah ? player.repeatRange : nil
        let style = style

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ReaderHeader(surah: surah)
                        .id(0)
                    ForEach(ayahs) { ayah in
                        let number = ayah.numberInSurah
                        AyahRow(
                            ayah: ayah,
                            isCurrent: number == current,
                            inRepeat: range?.contains(number) ?? false,
                            isBookmarked: bookmarks.isBookmarked(surah: surah.number, ayah: number),
                            isPicking: picking != nil,
                            isPickedFirst: picking == .last(first: number),
                            style: style,
                            onTap: { tap(ayah) }
                        )
                        .equatable()
                        .id(number)
                    }
                    footer
                }
            }
            .onScrollPhaseChange { _, phase in
                if phase == .tracking || phase == .interacting || phase == .decelerating { touch.last = Date() }
            }
            .onChange(of: player.ayah) { follow(proxy) }
            .onChange(of: router.readerRequest) { _, request in
                guard let request, request.surah == surah.number else { return }
                router.readerRequest = nil
                if request.pickRepeat { picking = .first }
                if let ayah = request.ayah { scroll(proxy, to: ayah) }
            }
            .task {
                // Let the lazy stack lay out once before jumping into it.
                guard let startAyah, startAyah > 1 else { return }
                try? await Task.sleep(for: .milliseconds(50))
                proxy.scrollTo(startAyah, anchor: .top)
            }
            .alert("Go to ayah", isPresented: $showGoTo) {
                TextField("1–\(surah.numberOfAyahs)", text: $goToText)
                    .keyboardType(.numberPad)
                Button("Go") {
                    if let number = Int(goToText), (1...surah.numberOfAyahs).contains(number) { scroll(proxy, to: number) }
                    goToText = ""
                }
                Button("Cancel", role: .cancel) { goToText = "" }
            }
        }
        .background(Palette.background)
        .navigationTitle(surah.englishName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let picking {
                PickBanner(picking: picking) {
                    withAnimation(Motion.standard) { self.picking = nil }
                }
                .transition(Motion.move(.move(edge: .top).combined(with: .opacity)))
            }
        }
        .animation(Motion.standard, value: picking)
        .sheet(item: $selected) { ayah in
            AyahActionsSheet(surah: surah, ayah: ayah) {
                withAnimation(Motion.standard) { picking = .last(first: ayah.numberInSurah) }
            }
        }
        .sheet(isPresented: $showType) { ReadingTypeSheet() }
        .onChange(of: translationId) { ayahs = QuranText.shared.ayahs(surah.number) }
        .onDisappear { NotificationCenter.default.post(name: .readerDidClose, object: nil) }
    }

    // MARK: Actions

    private func tap(_ ayah: Ayah) {
        switch picking {
        case .first:
            Haptics.selection()
            picking = .last(first: ayah.numberInSurah)
        case .last(let first):
            Haptics.success()
            picking = nil
            player.setRepeat(in: surah, from: first, to: ayah.numberInSurah)
        case nil:
            Haptics.tap()
            selected = ayah
        }
    }

    /// Keeps the ayah being recited in view, unless the reader was scrolled by hand
    /// in the last few seconds.
    private func follow(_ proxy: ScrollViewProxy) {
        guard isCurrentSurah, player.isPlaying, picking == nil, player.ayah > 0,
              Date().timeIntervalSince(touch.last) > 4 else { return }
        scroll(proxy, to: player.ayah)
    }

    private func scroll(_ proxy: ScrollViewProxy, to ayah: Int) {
        withAnimation(Motion.standard) { proxy.scrollTo(ayah, anchor: UnitPoint(x: 0.5, y: 0.2)) }
    }

    // MARK: Chrome

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isCurrentSurah, player.repeatRange != nil {
                RepeatMenu(onChooseAyahs: { picking = .first }) {
                    Image(systemName: "repeat.circle.fill")
                }
            } else {
                Button {
                    Haptics.tap()
                    picking = picking == nil ? .first : nil
                } label: {
                    Image(systemName: "repeat")
                }
                .accessibilityLabel("Repeat")
            }

            Button { showType = true } label: { Image(systemName: "textformat.size") }
                .accessibilityLabel("Reading type")

            Menu {
                if downloads.complete.contains(surah.number) {
                    Button("Remove download", systemImage: "trash", role: .destructive) { downloads.remove(surah.number) }
                } else if downloads.progress[surah.number] != nil {
                    Button("Cancel download", systemImage: "xmark") { downloads.cancel(surah.number) }
                } else {
                    Button("Download audio", systemImage: "arrow.down.circle") { downloads.download(surah) }
                }
                if surah.numberOfAyahs > 10 {
                    Button("Go to ayah…", systemImage: "number") { showGoTo = true }
                }
                Section {
                    if surah.number < 114 {
                        Button("Next surah", systemImage: "chevron.forward") { router.replaceReader(with: surah.number + 1) }
                    }
                    if surah.number > 1 {
                        Button("Previous surah", systemImage: "chevron.backward") { router.replaceReader(with: surah.number - 1) }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("Reader options")
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.sm) {
            if let previous = QuranText.shared.surah(surah.number - 1) {
                OutlineButton(label: previous.englishName, icon: "chevron.backward") { router.replaceReader(with: previous.number) }
            }
            if let next = QuranText.shared.surah(surah.number + 1) {
                OutlineButton(label: next.englishName, icon: "chevron.forward") { router.replaceReader(with: next.number) }
            }
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.xl)
    }
}

// MARK: - Header

private struct ReaderHeader: View {
    @Environment(Player.self) private var player
    let surah: Surah

    private var isCurrent: Bool { player.isCurrent(surah.number) }
    private var recent: Player.Recent? { player.recents.first { $0.surah == surah.number && $0.ayah > 1 } }

    private var playLabel: String {
        if isCurrent { return player.isPlaying ? "Pause" : "Continue from ayah \(player.ayah)" }
        if let recent { return "Continue from ayah \(recent.ayah)" }
        return "Play"
    }

    var body: some View {
        VStack(spacing: Spacing.xs) {
            Text(surah.name.replacingOccurrences(of: "سُورَةُ ", with: ""))
                .font(.appArabic(34))
                .foregroundStyle(Palette.textPrimary)
                .environment(\.layoutDirection, .rightToLeft)
            Text(surah.englishName)
                .font(TypeScale.title)
                .foregroundStyle(Palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("\(surah.englishNameTranslation) · \(surah.revelationType) · \(surah.numberOfAyahs) ayahs")
                .font(TypeScale.secondary)
                .foregroundStyle(Palette.textSecondary)

            Button {
                Haptics.impact(.light)
                if isCurrent {
                    player.toggle()
                } else if let recent {
                    player.play(recent)
                } else {
                    player.play(surah)
                }
            } label: {
                Label(playLabel, systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, Spacing.lg)
                    .frame(minHeight: MinSize.hitTarget)
                    .background(Capsule().fill(Color.brand))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(CardButtonStyle())
            .padding(.top, Spacing.sm)

            DiamondRule()
                .frame(width: 190)
                .padding(.top, Spacing.md)

            if surah.number != 1 && surah.number != 9 {
                Text("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ")
                    .font(.appArabic(24))
                    .foregroundStyle(Palette.textPrimary)
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.top, Spacing.sm)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }
}

// MARK: - Picking banner

private struct PickBanner: View {
    let picking: ReaderView.Picking
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "repeat")
                .font(.body.weight(.semibold))
                .foregroundStyle(.brand)
            Text(message)
                .font(TypeScale.body)
                .foregroundStyle(Palette.textPrimary)
            Spacer(minLength: Spacing.xs)
            Button("Cancel", action: cancel)
                .font(.body.weight(.semibold))
                .frame(minHeight: MinSize.hitTarget)
        }
        .padding(.horizontal, Spacing.screenMargin)
        .padding(.vertical, Spacing.xxs)
        .background(Palette.highlight)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        switch picking {
        case .first: "Tap the first ayah to repeat"
        case .last(let first): "Now tap the last ayah (ayah \(first) again for just that one)"
        }
    }
}

// MARK: - Ayah row

/// One ayah. Its inputs are plain values and `==` ignores the tap closure, so when
/// the ayah being recited changes only the two rows involved are redrawn, however
/// long the surah is. The Arabic is a single text, not a view per word.
struct AyahRow: View, Equatable {
    let ayah: Ayah
    let isCurrent: Bool
    let inRepeat: Bool
    let isBookmarked: Bool
    let isPicking: Bool
    let isPickedFirst: Bool
    let style: ReaderStyle
    let onTap: () -> Void

    static func == (a: AyahRow, b: AyahRow) -> Bool {
        a.ayah == b.ayah && a.isCurrent == b.isCurrent && a.inRepeat == b.inRepeat
            && a.isBookmarked == b.isBookmarked && a.isPicking == b.isPicking
            && a.isPickedFirst == b.isPickedFirst && a.style == b.style
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                marker
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    arabic
                        .lineSpacing(style.arabicSize * 0.45)
                        .foregroundStyle(Palette.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                    if style.showTransliteration, !ayah.transliteration.isEmpty {
                        Text(ayah.transliteration)
                            .font(style.serif.font(size: style.transliterationSize, italic: true, scales: false))
                            .foregroundStyle(Palette.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                    if style.showTranslation, !ayah.translation.isEmpty {
                        Text(ayah.translation)
                            .font(style.serif.font(size: style.translationSize, scales: false))
                            .foregroundStyle(Palette.textPrimary)
                            .lineSpacing(3)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenMargin)
            .padding(.vertical, Spacing.md)
            .background(isCurrent || isPickedFirst ? Palette.highlight : Color.clear)
            .overlay(alignment: .leading) {
                // A rule down the side marks the ayahs a repeat covers.
                if inRepeat { Rectangle().fill(Color.brand).frame(width: 3) }
            }
            .overlay(alignment: .bottom) { Hairline().padding(.leading, Spacing.screenMargin) }
            .contentShape(Rectangle())
            .animation(Motion.standard, value: isCurrent)
            .animation(Motion.standard, value: inRepeat)
        }
        .buttonStyle(AyahPressStyle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ayah \(ayah.numberInSurah)")
        .accessibilityValue(ayah.translation)
        .accessibilityHint(isPicking ? "Chooses this ayah" : "Shows actions for this ayah")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    @ViewBuilder private var arabic: some View {
        let font = style.arabic.font(size: style.arabicSize, scales: false)
        if isCurrent {
            RecitedArabic(ayah: ayah, font: font)
        } else {
            Text(ayah.arabic).font(font)
        }
    }

    private var marker: some View {
        VStack(spacing: Spacing.xs) {
            if isPicking {
                Image(systemName: isPickedFirst ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isPickedFirst ? Color.brand : Palette.textTertiary)
                    .frame(height: 22)
            }
            Text("\(ayah.numberInSurah)")
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(isCurrent ? Color.brand : Palette.textSecondary)
            if isBookmarked {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundStyle(.brand)
            }
        }
        .frame(width: 30)
        .padding(.top, 6)
    }
}

/// A quiet press state for a whole ayah: it dims, it doesn't shrink.
private struct AyahPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}
