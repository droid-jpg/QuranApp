import SwiftUI

/// The reader's "Repeat" sheet. Leads with the three memorization drills as
/// one-tap presets (Listen · Repeat · Chain) built around the ayah in focus, then
/// tucks the full manual controls (scope, repeat count, pause) into a compact
/// "Custom" section. Presets start playback immediately; Custom stages a loop that
/// applies on the next play.
struct LoopSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: LoopSettings
    @State private var showAyahPicker = false
    let totalAyahs: Int
    /// Loaded ayahs for the surah, so the segment picker can show real text.
    /// May be empty if the reader hasn't finished loading; the picker then falls
    /// back to showing ayah numbers only.
    let ayahs: [Ayah]
    /// The ayah the presets center on — normally the one playing or being read.
    let focusAyah: Int
    /// Stage a loop for the next play (Custom → Apply).
    let onApply: (LoopSettings) -> Void
    /// Start a preset loop playing right now.
    var onStartPreset: (LoopSettings) -> Void = { _ in }

    init(settings: LoopSettings, totalAyahs: Int, ayahs: [Ayah], focusAyah: Int = 1,
         onApply: @escaping (LoopSettings) -> Void,
         onStartPreset: @escaping (LoopSettings) -> Void = { _ in }) {
        _settings = State(initialValue: settings)
        self.totalAyahs = totalAyahs
        self.ayahs = ayahs
        self.focusAyah = max(1, min(focusAyah, max(totalAyahs, 1)))
        self.onApply = onApply
        self.onStartPreset = onStartPreset
    }

    private func startPreset(_ preset: LoopSettings) {
        Haptics.tap()
        onStartPreset(preset)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Memorization presets
                Section {
                    PresetRow(icon: "repeat", title: "Listen",
                              subtitle: "Loop ayah \(focusAyah) back-to-back") {
                        startPreset(.listen(ayah: focusAyah))
                    }
                    PresetRow(icon: "pause.circle", title: "Repeat",
                              subtitle: "Play ayah \(focusAyah), then pause for you to recite") {
                        startPreset(.repeatAfter(ayah: focusAyah))
                    }
                    if focusAyah > 1 {
                        PresetRow(icon: "link", title: "Chain",
                                  subtitle: "Recite ayahs 1–\(focusAyah), pausing after each") {
                            startPreset(.chain(from: 1, through: focusAyah, pause: true))
                        }
                    }
                } header: {
                    Text("Memorize")
                } footer: {
                    Text("Quick drills for the ayah you're working on. Starts playing right away.")
                }

                // MARK: Custom
                Section {
                    Picker("Repeat", selection: $settings.mode) {
                        Text("Off").tag(LoopSettings.Mode.off)
                        Text("This ayah").tag(LoopSettings.Mode.single)
                        Text("Range").tag(LoopSettings.Mode.segment)
                    }
                    .pickerStyle(.segmented)

                    if settings.mode == .single {
                        Stepper(value: $settings.startAyah, in: 1...max(totalAyahs, 1)) {
                            HStack {
                                Text("Ayah")
                                Spacer()
                                Text("\(settings.startAyah)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .onChange(of: settings.startAyah) { _, v in settings.endAyah = v }
                    }

                    if settings.mode == .segment {
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

                    if settings.mode != .off {
                        Picker("Times", selection: $settings.repeatCount) {
                            Text("∞").tag(0)
                            ForEach([1, 2, 3, 5, 7, 10], id: \.self) { Text("\($0)×").tag($0) }
                        }
                        Toggle("Pause to repeat", isOn: $settings.listenAndRepeat)
                        if settings.listenAndRepeat {
                            Picker("Gap", selection: $settings.listenRepeatDelay) {
                                ForEach(LoopSettings.RepeatDelay.allCases) { d in
                                    Text(d.label).tag(d)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Custom")
                } footer: {
                    if settings.mode == .off {
                        Text("Playback advances through the surah normally.")
                    } else if settings.listenAndRepeat {
                        Text("After each ayah, audio pauses so you can repeat it aloud, then continues the loop.")
                    } else {
                        Text(settings.repeatCount == 0
                             ? "Loops until you stop playback."
                             : "Plays \(settings.repeatCount) time\(settings.repeatCount == 1 ? "" : "s"), then stops.")
                    }
                }
            }
            .navigationTitle("Repeat")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: settings.mode) { _, newMode in
                switch newMode {
                case .single:
                    settings.startAyah = min(max(settings.startAyah, 1), totalAyahs)
                    settings.endAyah = settings.startAyah
                case .segment:
                    settings.startAyah = min(max(settings.startAyah, 1), totalAyahs)
                    settings.endAyah = min(max(settings.endAyah, settings.startAyah), totalAyahs)
                case .off:
                    break
                }
            }
            .sheet(isPresented: $showAyahPicker) {
                AyahRangePicker(
                    ayahs: ayahs,
                    totalAyahs: totalAyahs,
                    initialStart: settings.startAyah,
                    initialEnd: settings.endAyah
                ) { start, end in
                    settings.startAyah = start
                    settings.endAyah = end
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
        settings.startAyah == settings.endAyah
            ? "Ayah \(settings.startAyah)"
            : "Ayahs \(settings.startAyah)–\(settings.endAyah)"
    }

    private var segmentRangeSubtitle: String {
        let count = settings.endAyah - settings.startAyah + 1
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
                    .font(.system(size: 18))
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
                    .font(.system(size: 22))
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
/// ayah between them highlight in teal — mirroring `WordLoopPickerView`.
private struct AyahRangePicker: View {
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
                VStack(spacing: 6) {
                    Text(instruction)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(awaitingEnd ? Color.brand : .primary)
                        .animation(.default, value: awaitingEnd)
                    HStack(spacing: 8) {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if !(start == 1 && end == totalAyahs && !awaitingEnd) {
                            Button("Whole Surah") {
                                start = 1; end = totalAyahs; awaitingEnd = false
                                Haptics.selection()
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.brand)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color(.secondarySystemBackground))

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(rowNumbers, id: \.self) { n in
                                AyahSelectRow(
                                    number: n,
                                    ayah: ayahByNumber[n],
                                    state: state(for: n)
                                )
                                .id(n)
                                .onTapGesture { handleTap(n) }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
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
        VStack(alignment: .trailing, spacing: 8) {
            HStack {
                if let endpointLabel {
                    Text(endpointLabel)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.brand))
                }
                Spacer()
                Text("\(number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isSelected ? .white : Color(.secondaryLabel))
                    .frame(width: 26, height: 26)
                    .background(isSelected ? Color.brand : Color(.tertiarySystemFill))
                    .clipShape(Circle())
            }

            if let ayah {
                Text(ayah.arabic)
                    .font(.system(size: 22))
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(maxWidth: .infinity, alignment: .trailing)

                if !ayah.transliteration.isEmpty {
                    Text(ayah.transliteration)
                        .font(.system(size: 13, weight: .light))
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !ayah.translation.isEmpty {
                    Text(ayah.translation)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(.label).opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("Ayah \(number)")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(rowBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(borderColor, lineWidth: isEndpoint ? 2 : 1)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var rowBackground: Color {
        switch state {
        case .normal:               return Color(.secondarySystemGroupedBackground)
        case .inRange:              return Color.brand.opacity(0.12)
        case .start, .end, .single: return Color.brand.opacity(0.18)
        }
    }

    private var borderColor: Color {
        switch state {
        case .start, .end, .single: return .brand
        case .inRange:              return .brand.opacity(0.4)
        case .normal:               return .clear
        }
    }
}
