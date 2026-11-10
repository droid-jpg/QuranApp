import SwiftUI

/// The reader's "Repeat" sheet. Leads with the three memorization drills as
/// one-tap presets (Listen · Repeat · Chain) built around the ayah in focus, then
/// tucks the full manual controls (scope, repeat count, pause) into a compact
/// "Custom" section. Presets start playback immediately; Custom stages a loop that
/// applies on the next play.
struct LoopSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: RepeatState
    @State private var showAyahPicker = false
    let surah: Int
    let totalAyahs: Int
    /// Loaded ayahs for the surah, so the segment picker can show real text.
    /// May be empty if the reader hasn't finished loading; the picker then falls
    /// back to showing ayah numbers only.
    let ayahs: [Ayah]
    /// The ayah the presets center on — normally the one playing or being read.
    let focusAyah: Int
    /// Stage a repeat (Custom → Apply).
    let onApply: (RepeatState) -> Void
    /// Start a preset repeat playing right now.
    var onStartPreset: (RepeatState) -> Void = { _ in }

    init(settings: RepeatState, surah: Int, totalAyahs: Int, ayahs: [Ayah], focusAyah: Int = 1,
         onApply: @escaping (RepeatState) -> Void,
         onStartPreset: @escaping (RepeatState) -> Void = { _ in }) {
        _settings = State(initialValue: settings)
        self.surah = surah
        self.totalAyahs = totalAyahs
        self.ayahs = ayahs
        self.focusAyah = max(1, min(focusAyah, max(totalAyahs, 1)))
        self.onApply = onApply
        self.onStartPreset = onStartPreset
    }

    private func startPreset(_ preset: RepeatState) {
        Haptics.tap()
        onStartPreset(preset)
        dismiss()
    }

    /// The old Off / This ayah / Range picker, mapped onto `RepeatState`.
    private var scope: Binding<PlayerScope> {
        Binding(
            get: { !settings.isOn ? .off : settings.isSingleAyah ? .ayah : .range },
            set: { new in
                switch new {
                case .off:
                    settings.isOn = false
                case .ayah:
                    settings = settings.switchedOn(surah: surah, currentAyah: focusAyah)
                        .clamped(ayahCount: totalAyahs)
                    settings.to = settings.from
                case .range:
                    settings = settings.switchedOn(surah: surah, currentAyah: focusAyah)
                        .clamped(ayahCount: totalAyahs)
                    // A range needs two ayahs to differ from "This ayah".
                    if settings.isSingleAyah, totalAyahs > 1 {
                        if settings.to < totalAyahs { settings.to += 1 } else { settings.from -= 1 }
                    }
                }
            }
        )
    }

    /// "Pause to repeat" is now just "pause is not None".
    private var pauses: Binding<Bool> {
        Binding(
            get: { settings.pause != .none },
            set: { settings.pause = $0 ? .ayahLength : .none }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Memorization presets
                Section {
                    PresetRow(icon: "repeat", title: "Listen",
                              subtitle: "Loop ayah \(focusAyah) back-to-back") {
                        startPreset(.repeatThisAyah(surah: surah, ayah: focusAyah))
                    }
                    PresetRow(icon: "pause.circle", title: "Repeat",
                              subtitle: "Play ayah \(focusAyah), then pause for you to recite") {
                        startPreset(.listenThenRecite(surah: surah, ayah: focusAyah))
                    }
                    if focusAyah > 1 {
                        PresetRow(icon: "link", title: "Chain",
                                  subtitle: "Loop ayahs \(RepeatState.joinRange(ending: focusAyah).lowerBound)–\(focusAyah) together") {
                            startPreset(.joinWithPrevious2(surah: surah, ayah: focusAyah))
                        }
                    }
                } header: {
                    Text("Memorize")
                } footer: {
                    Text("Quick drills for the ayah you're working on. Starts playing right away.")
                }

                // MARK: Custom
                Section {
                    Picker("Repeat", selection: scope) {
                        Text("Off").tag(PlayerScope.off)
                        Text("This ayah").tag(PlayerScope.ayah)
                        Text("Range").tag(PlayerScope.range)
                    }
                    .pickerStyle(.segmented)

                    if scope.wrappedValue == .ayah {
                        Stepper(value: $settings.from, in: 1...max(totalAyahs, 1)) {
                            HStack {
                                Text("Ayah")
                                Spacer()
                                Text("\(settings.from)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .onChange(of: settings.from) { _, v in
                            if scope.wrappedValue == .ayah || settings.to < v { settings.to = v }
                        }
                    }

                    if scope.wrappedValue == .range {
                        Button { showAyahPicker = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                                    .foregroundStyle(.brand)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(segmentRangeTitle).foregroundStyle(.primary)
                                    Text(segmentRangeSubtitle)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if settings.isOn {
                        Picker("Times", selection: $settings.times) {
                            ForEach([RepeatState.Times.infinite, .two, .three, .five, .ten]) { t in
                                Text(t.count.map { "\($0)×" } ?? "∞").tag(t)
                            }
                        }
                        Toggle("Pause to repeat", isOn: pauses)
                        if settings.pause != .none {
                            Picker("Gap", selection: $settings.pause) {
                                Text("Match ayah length").tag(RepeatState.Pause.ayahLength)
                                Text("5 seconds").tag(RepeatState.Pause.seconds(5))
                                Text("10 seconds").tag(RepeatState.Pause.seconds(10))
                            }
                        }
                    }
                } header: {
                    Text("Custom")
                } footer: {
                    if !settings.isOn {
                        Text("Playback advances through the surah normally.")
                    } else if settings.pause != .none {
                        Text("After each ayah, audio pauses so you can repeat it aloud, then continues the loop.")
                    } else if let n = settings.times.count {
                        Text("Plays \(n) times, then carries on.")
                    } else {
                        Text("Loops until you stop playback.")
                    }
                }
            }
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAyahPicker) {
                AyahRangePickerSheet(
                    ayahs: ayahs,
                    totalAyahs: totalAyahs,
                    initialStart: settings.from,
                    initialEnd: settings.to
                ) { start, end in
                    settings.from = min(start, end)
                    settings.to = max(start, end)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(settings)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var segmentRangeTitle: String {
        settings.from == settings.to
            ? "Ayah \(settings.from)"
            : "Ayahs \(settings.from)–\(settings.to)"
    }

    private var segmentRangeSubtitle: String {
        let count = settings.to - settings.from + 1
        return "\(count) ayah\(count == 1 ? "" : "s") selected"
    }
}

// MARK: - Preset row

private struct PresetRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.label(18))
                    .foregroundStyle(.brand)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.label(22))
                    .foregroundStyle(.brand)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ayah range picker

/// Full-height selector that lists every ayah with its Arabic, transliteration,
/// and translation. Tap the first ayah, then the last; the endpoints and every
/// ayah between them are marked in the accent.
///
/// Also the reader's answer to "set a loop range": the expanded player opens this
/// instead of asking anyone to drag two unlabelled handles along a rail.
struct AyahRangePickerSheet: View {
    let totalAyahs: Int
    let onSelect: (Int, Int) -> Void
    private let ayahByNumber: [Int: Ayah]

    @Environment(\.dismiss) private var dismiss
    @State private var start: Int
    @State private var end: Int
    /// When true, the next tap sets the end ayah; otherwise it begins a new
    /// selection by setting the start.
    @State private var awaitingEnd = false

    init(ayahs: [Ayah], totalAyahs: Int, initialStart: Int, initialEnd: Int,
         onSelect: @escaping (Int, Int) -> Void) {
        self.totalAyahs = totalAyahs
        self.onSelect = onSelect
        self.ayahByNumber = Dictionary(ayahs.map { ($0.numberInSurah, $0) }, uniquingKeysWith: { first, _ in first })
        _start = State(initialValue: initialStart)
        _end = State(initialValue: initialEnd)
    }

    private var rowNumbers: [Int] { Array(1...max(totalAyahs, 1)) }

    private var instruction: String {
        awaitingEnd ? "Now tap the last ayah of the loop" : "Tap an ayah to set the start"
    }

    private var summary: String {
        if awaitingEnd { return "Starting at ayah \(start)" }
        if start == end { return "Looping ayah \(start) only" }
        return "Looping ayahs \(start)–\(end) · \(end - start + 1) ayahs"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Instruction + live summary banner
                VStack(spacing: 7) {
                    Text(instruction)
                        .font(.appSerif(17, weight: .medium))
                        .foregroundStyle(awaitingEnd ? Color.brand : Color(.label))
                        .animation(.default, value: awaitingEnd)
                    HStack(spacing: 10) {
                        MetaText(summary.uppercased(), size: 9.5)
                        if !(start == 1 && end == totalAyahs && !awaitingEnd) {
                            Button("Whole surah") {
                                start = 1; end = totalAyahs; awaitingEnd = false
                                Haptics.selection()
                            }
                            .font(.label(9.5, weight: .semibold))
                            .kerning(1)
                            .textCase(.uppercase)
                            .foregroundStyle(.brand)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 16)

                Hairline()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rowNumbers, id: \.self) { n in
                                AyahSelectRow(
                                    number: n,
                                    ayah: ayahByNumber[n],
                                    state: state(for: n)
                                )
                                .id(n)
                                .onTapGesture { handleTap(n) }
                                Hairline()
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(start, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("Select Ayahs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSelect(start, end)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func state(for n: Int) -> AyahSelectRow.SelectionState {
        // While picking the end, only the committed start is highlighted.
        if awaitingEnd { return n == start ? .start : .normal }
        if start == end { return n == start ? .single : .normal }
        if n == start { return .start }
        if n == end { return .end }
        if n > start && n < end { return .inRange }
        return .normal
    }

    private func handleTap(_ n: Int) {
        if awaitingEnd {
            if n < start {
                end = start
                start = n
            } else {
                end = n
            }
            awaitingEnd = false
        } else {
            start = n
            end = n
            awaitingEnd = true
        }
        Haptics.selection()
    }
}

// MARK: - Ayah selection row

private struct AyahSelectRow: View {
    enum SelectionState { case normal, start, end, single, inRange }

    let number: Int
    let ayah: Ayah?
    let state: SelectionState

    private var isEndpoint: Bool { state == .start || state == .end || state == .single }
    private var isSelected: Bool { state != .normal }

    private var endpointLabel: String? {
        switch state {
        case .start:  return "Start"
        case .end:    return "End"
        case .single: return "Loop"
        default:      return nil
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 9) {
            HStack(spacing: 8) {
                if let endpointLabel {
                    Text(endpointLabel.uppercased())
                        .font(.label(9, weight: .bold))
                        .kerning(1.2)
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Rectangle().fill(Color.brand))
                }
                Spacer()
                MetaText("\(number)", tint: isSelected ? .brand : Color.secondary, size: 11)
            }

            if let ayah {
                Text(ayah.arabic)
                    .font(.appArabic(21))
                    .lineSpacing(9)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if !ayah.transliteration.isEmpty {
                    Text(ayah.transliteration)
                        .font(.appSerif(13, weight: .light, italic: true))
                        .foregroundStyle(Color.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !ayah.translation.isEmpty {
                    Text(ayah.translation)
                        .font(.appSerif(14))
                        .foregroundStyle(Color(.label).opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Ayah \(number)")
                    .font(.appSerif(17, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(alignment: .leading) {
            // Selection is a rule in the margin and a wash, not a filled card —
            // the same mark the reader puts beside the ayah being recited.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.brand)
                    .frame(width: isEndpoint ? 3 : (state == .inRange ? 1.5 : 0))
                Rectangle()
                    .fill(Color.brand.opacity(isSelected ? 0.07 : 0))
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
