import SwiftUI

struct LoopSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: LoopSettings
    let totalAyahs: Int
    let onApply: (LoopSettings) -> Void

    init(settings: LoopSettings, totalAyahs: Int, onApply: @escaping (LoopSettings) -> Void) {
        _settings = State(initialValue: settings)
        self.totalAyahs = totalAyahs
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Mode picker
                Section("Loop Mode") {
                    ForEach(LoopSettings.Mode.allCases) { mode in
                        HStack(spacing: 12) {
                            Image(systemName: mode.icon)
                                .foregroundStyle(.teal)
                                .frame(width: 22)
                            Text(mode.rawValue)
                            Spacer()
                            if settings.mode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.teal)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { settings.mode = mode }
                    }
                }

                // MARK: Segment range (only shown in segment mode)
                if settings.mode == .segment {
                    Section("Segment Range") {
                        Picker("Start", selection: $settings.startAyah) {
                            ForEach(1...totalAyahs, id: \.self) { Text("Ayah \($0)").tag($0) }
                        }
                        Picker("End", selection: $settings.endAyah) {
                            ForEach(settings.startAyah...totalAyahs, id: \.self) { Text("Ayah \($0)").tag($0) }
                        }
                    }
                    .onChange(of: settings.startAyah) { _, newStart in
                        if settings.endAyah < newStart { settings.endAyah = newStart }
                    }
                }

                // MARK: Repeat count (hidden when loop is off)
                if settings.mode != .off {
                    Section {
                        Picker("Repeat", selection: $settings.repeatCount) {
                            Text("∞  Infinite").tag(0)
                            ForEach([1, 2, 3, 5, 7, 10], id: \.self) { Text("\($0)×").tag($0) }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 130)
                    } header: {
                        Text("Repeat Count")
                    } footer: {
                        Text(settings.repeatCount == 0
                             ? "Loops until you stop playback."
                             : "Plays the loop \(settings.repeatCount) time\(settings.repeatCount == 1 ? "" : "s") then stops.")
                    }
                }

                // MARK: Listen & Repeat
                Section {
                    Toggle("Listen & Repeat", isOn: $settings.listenAndRepeat)
                    if settings.listenAndRepeat {
                        Picker("Pause duration", selection: $settings.listenRepeatDelay) {
                            ForEach(LoopSettings.RepeatDelay.allCases) { d in
                                Text(d.label).tag(d)
                            }
                        }
                    }
                } header: {
                    Text("Listen & Repeat")
                } footer: {
                    if settings.listenAndRepeat {
                        Text("After each ayah plays, audio pauses for the selected duration so you can repeat it aloud.")
                    }
                }
            }
            .navigationTitle("Playback Settings")
            .navigationBarTitleDisplayMode(.inline)
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
}
