import SwiftUI

struct DhikrView: View {
    @StateObject private var store = DhikrStore()
    @State private var showGoalEditor = false
    @State private var draftGoal: String = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Preset scroll
                    presetPicker
                        .padding(.top, 8)

                    Spacer()

                    // Central counter button
                    counterButton

                    Spacer()

                    // Bottom bar: goal / reset
                    bottomBar
                }
            }
            .navigationTitle("Dhikr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showGoalEditor = true } label: {
                        Label("Set Goal", systemImage: "target")
                    }
                }
            }
            .sheet(isPresented: $showGoalEditor) {
                GoalEditorSheet(goal: $store.customGoal) {
                    store.reset()
                }
            }
        }
    }

    // MARK: - Preset strip

    private var presetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DhikrStore.defaultPresets) { preset in
                    let active = store.selectedPreset.id == preset.id
                    Button {
                        withAnimation(.spring(duration: 0.25)) { store.select(preset) }
                    } label: {
                        Text(preset.name)
                            .font(.subheadline.weight(active ? .semibold : .regular))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                active ? Color.teal : Color(.secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                            .foregroundStyle(active ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Counter button

    private var counterButton: some View {
        ZStack {
            // Outer glow when goal reached
            if store.goalReached {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 300, height: 300)
                    .transition(.scale.combined(with: .opacity))
            }

            // Progress ring
            Circle()
                .stroke(Color.teal.opacity(0.15), lineWidth: 14)
                .frame(width: 240, height: 240)

            Circle()
                .trim(from: 0, to: store.progress)
                .stroke(
                    store.goalReached ? Color.green : Color.teal,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 240, height: 240)
                .animation(.spring(duration: 0.3), value: store.progress)

            // Tap surface
            Button(action: store.tap) {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(width: 200, height: 200)
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)

                    VStack(spacing: 6) {
                        if store.goalReached {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(.green)
                                .transition(.scale.combined(with: .opacity))
                        } else {
                            Text("\(store.count)")
                                .font(.system(size: 64, weight: .thin, design: .rounded))
                                .contentTransition(.numericText(countsDown: false))
                                .animation(.spring(duration: 0.2), value: store.count)
                        }

                        Text(store.selectedPreset.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(TapScaleStyle())
            .disabled(store.goalReached)
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        HStack {
            // Goal indicator
            VStack(alignment: .leading, spacing: 2) {
                Text("Goal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(store.count) / \(store.goal)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(store.goalReached ? .green : .primary)
            }

            Spacer()

            // Session summary
            if !store.sessionCounts.isEmpty {
                VStack(alignment: .center, spacing: 2) {
                    Text("Session total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(store.sessionCounts.values.reduce(0, +))")
                        .font(.headline.monospacedDigit())
                }
            }

            Spacer()

            // Reset
            Button(action: store.reset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .font(.subheadline)
                    .foregroundStyle(.teal)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.regularMaterial)
    }
}

// MARK: - Goal editor sheet

struct GoalEditorSheet: View {
    @Binding var goal: Int
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftGoal: Int = 33

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Goal: \(draftGoal)", value: $draftGoal, in: 1...1000)

                    let presets = [7, 10, 33, 34, 99, 100, 200, 500, 1000]
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(presets, id: \.self) { n in
                                Button("\(n)") {
                                    draftGoal = n
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(draftGoal == n ? Color.teal : Color(.tertiarySystemGroupedBackground), in: Capsule())
                                .foregroundStyle(draftGoal == n ? .white : .primary)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Set your goal")
                } footer: {
                    Text("You'll get a stronger vibration when you reach this count.")
                }
            }
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        goal = draftGoal
                        onConfirm()
                        dismiss()
                    }
                }
            }
            .onAppear { draftGoal = goal }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Press-scale button style

struct TapScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
    }
}
