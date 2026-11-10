import SwiftUI

/// The one Repeat control (REDESIGN §3.6). Every change goes straight to
/// `AudioService.setRepeat`, so there is nothing to cancel or apply; the only bar
/// button is Done.
///
/// It edits the repeat for `surah`. When the service's state names another surah,
/// the sheet shows what switching on here would give (this surah, the focus ayah,
/// ∞) and stays off until the switch is turned on; that write then moves the one
/// repeat state to this surah, inert until playback starts here (see
/// `AudioService.repeatState`).
struct RepeatSheet: View {
    let surah: Surah
    /// Loaded ayahs, for the Arabic previews. May be empty; the rows then show
    /// numbers only.
    let ayahs: [Ayah]
    /// The ayah a fresh repeat starts on when nothing in this surah is playing.
    let focusAyah: Int

    @EnvironmentObject private var audioService: AudioService
    @Environment(\.dismiss) private var dismiss
    @State private var picking: RangeEnd?
    /// Measured heights, so the sheet opens exactly tall enough for everything
    /// down to the summary and Play button.
    @State private var headerHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private var type = ReadingType()

    init(surah: Surah, ayahs: [Ayah], focusAyah: Int) {
        self.surah = surah
        self.ayahs = ayahs
        self.focusAyah = max(1, min(focusAyah, max(surah.numberOfAyahs, 1)))
    }

    fileprivate enum RangeEnd: String, Identifiable {
        case from = "From", to = "To"
        var id: String { rawValue }
    }

    private var total: Int { max(1, surah.numberOfAyahs) }

    private var isLoadedHere: Bool { audioService.currentSurah == surah.number && audioService.currentAyah != nil }

    /// The ayah "this ayah" means: the one playing here, else the focus ayah.
    private var liveAyah: Int {
        if isLoadedHere, let a = audioService.currentAyah { return min(a, total) }
        return focusAyah
    }

    /// What the sheet shows and edits.
    private var state: RepeatState {
        let s = audioService.repeatState
        if s.surah == surah.number { return s.clamped(ayahCount: total) }
        var fresh = s.switchedOn(surah: surah.number, currentAyah: liveAyah).clamped(ayahCount: total)
        fresh.isOn = false
        return fresh
    }

    private func update(_ change: (inout RepeatState) -> Void) {
        var s = state
        change(&s)
        audioService.setRepeat(s.clamped(ayahCount: total))
    }

    // MARK: Edits

    private var isOn: Binding<Bool> {
        Binding(
            get: { state.isOn },
            set: { on in
                Haptics.selection()
                if on {
                    audioService.setRepeat(audioService.repeatState
                        .switchedOn(surah: surah.number, currentAyah: liveAyah)
                        .clamped(ayahCount: total))
                } else {
                    update { $0.isOn = false }
                }
            }
        )
    }

    /// From never passes To: moving one past the other drags the other along.
    private func set(_ end: RangeEnd, to n: Int) {
        let n = min(max(1, n), total)
        update { s in
            switch end {
            case .from: s.from = n; if s.to < n { s.to = n }
            case .to:   s.to = n;   if s.from > n { s.from = n }
            }
        }
    }

    private func value(_ end: RangeEnd) -> Int { end == .from ? state.from : state.to }

    private var times: Binding<RepeatState.Times> {
        Binding(get: { state.times }, set: { t in update { $0.times = t } })
    }

    private var pause: Binding<RepeatState.Pause> {
        Binding(get: { state.pause }, set: { p in update { $0.pause = p } })
    }

    /// The Play button is only needed while this surah isn't already playing;
    /// otherwise every change is already live.
    private var showsPlay: Bool { !(audioService.isPlaying && audioService.currentSurah == surah.number) }

    private var playLabel: String {
        state.isSingleAyah ? "Play ayah \(state.from)" : "Play ayahs \(state.from)–\(state.to)"
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headerHeight = $0 }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(spacing: 0) {
                            endRow(.from)
                            Hairline()
                            endRow(.to)
                        }
                        shortcuts
                        segmentedRow("Times", selection: times,
                                     options: RepeatState.Times.allCases.map { EditorialOption($0, $0.label) })
                        segmentedRow("Pause after each ayah", selection: pause,
                                     options: RepeatState.Pause.allCases.map { EditorialOption($0, $0.label) })
                    }
                    .disabled(!state.isOn)
                    .opacity(state.isOn ? 1 : 0.4)

                    Text(state.summary)
                        .font(.label(15))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsPlay {
                        playButton
                            .disabled(!state.isOn)
                            .opacity(state.isOn ? 1 : 0.4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
                .animation(AppAnim.smooth, value: state.isOn)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemBackground))
        .tint(.brand)
        // Sized to the content (the detent height excludes the bottom safe area);
        // large stays available for big Dynamic Type, where the content scrolls.
        .presentationDetents(fitDetents, selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: fitDetents) { _, new in
            if !new.contains(detent) { detent = new.first { $0 != .large } ?? .large }
        }
        // Opaque: the reader must not show through (AUDIT #21).
        .presentationBackground(Color(.systemBackground))
    }

    @State private var detent: PresentationDetent = .medium

    private var fitDetents: Set<PresentationDetent> {
        guard headerHeight > 0, contentHeight > 0 else { return [.medium, .large] }
        return [.height(headerHeight + contentHeight), .large]
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Repeat")
                    .font(type.serif(22, weight: .medium))
                    .foregroundStyle(Color.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(surah.englishName)
                    .font(.label(15))
                    .foregroundStyle(Color.secondary)
            }
            Spacer(minLength: 8)
            Toggle("Repeat", isOn: isOn)
                .labelsHidden()
                .tint(.brand)
            // The sheet's only bar button: every change is already applied.
            Button { dismiss() } label: {
                Text("Done")
                    .font(.label(17, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .fixedSize()
                    .frame(minWidth: BarButton.side, minHeight: BarButton.side)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
    }

    /// "From  Ayah 3  ·  <first words>  −  +". The number opens a wheel; VoiceOver
    /// gets one adjustable element labelled with the row's visible title.
    private func endRow(_ end: RangeEnd) -> some View {
        let n = value(end)
        return HStack(spacing: 8) {
            Text(end.rawValue)
                .font(.label(17))
                .foregroundStyle(Color.ink)
                .fixedSize()
                .frame(minWidth: 44, alignment: .leading)

            Button { Haptics.tap(); picking = end } label: {
                Text("Ayah \(n)")
                    .font(.label(17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color.brand)
                    .fixedSize()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(get: { picking == end }, set: { if !$0 { picking = nil } })) {
                wheel(end)
            }

            Spacer(minLength: 4)

            if let preview = preview(n) {
                Text(preview)
                    .font(type.arabic(18))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .environment(\.layoutDirection, .rightToLeft)
                    .layoutPriority(-1)
            }

            stepButton("minus", enabled: n > 1) { set(end, to: n - 1) }
            stepButton("plus", enabled: n < total) { set(end, to: n + 1) }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(end.rawValue)
        .accessibilityValue("Ayah \(n)")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: set(end, to: n + 1)
            case .decrement: set(end, to: n - 1)
            @unknown default: break
            }
        }
        .accessibilityAction { picking = end }
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            Image(systemName: icon)
                .font(.label(15, weight: .semibold))
                .foregroundStyle(enabled ? Color.brand : Color(.tertiaryLabel))
                .frame(width: BarButton.side, height: BarButton.side)
                .overlay(Rectangle().strokeBorder(Color(.label).opacity(0.18), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func wheel(_ end: RangeEnd) -> some View {
        Picker(end.rawValue, selection: Binding(get: { value(end) }, set: { set(end, to: $0) })) {
            ForEach(1...total, id: \.self) { n in
                Text("Ayah \(n)").tag(n)
            }
        }
        .pickerStyle(.wheel)
        .frame(width: 240, height: 200)
        .presentationCompactAdaptation(.popover)
        .presentationBackground(Color(.systemBackground))
    }

    private var shortcuts: some View {
        HStack(spacing: 8) {
            shortcut("This ayah only", selected: state.isSingleAyah) {
                update { $0.from = liveAyah; $0.to = liveAyah }
            }
            shortcut("Whole surah", selected: state.from == 1 && state.to == total) {
                update { $0.from = 1; $0.to = total }
            }
            Spacer(minLength: 0)
        }
    }

    private func shortcut(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button { Haptics.selection(); action() } label: {
            Text(title)
                .font(.label(15, weight: .semibold))
                .foregroundStyle(selected ? Color.brand : Color.ink.opacity(0.72))
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(minHeight: BarButton.side)
                .overlay(Rectangle().strokeBorder(selected ? Color.brand : Color(.label).opacity(0.18),
                                                  lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A labelled segmented control, or the same choice as a menu row when the
    /// segments would not fit untruncated (large Dynamic Type).
    private func segmentedRow<V: Hashable>(_ title: String, selection: Binding<V>,
                                           options: [EditorialOption<V>]) -> some View {
        ViewThatFits(in: .horizontal) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.label(17))
                    .foregroundStyle(Color.ink)
                EditorialSegmented(selection: selection, options: options, capitals: false)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(title)
            }
            EditorialMenuRow(title: title, selection: selection, options: options)
                .frame(minHeight: BarButton.side)
        }
    }

    private var playButton: some View {
        Button {
            Haptics.tap()
            var s = state
            s.isOn = true
            audioService.startRepeat(s, totalAyahs: total, surahName: surah.englishName)
            dismiss()
        } label: {
            Text(playLabel)
                .font(.label(17, weight: .semibold))
                .foregroundStyle(Color(.systemBackground))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(Rectangle().fill(Color.brand))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The first few words of an ayah, enough to recognise it.
    private func preview(_ n: Int) -> String? {
        guard let text = ayahs.first(where: { $0.numberInSurah == n })?.arabic, !text.isEmpty else { return nil }
        return text.split(whereSeparator: \.isWhitespace).prefix(3).joined(separator: " ")
    }
}
