import SwiftUI

/// The tasbih. The counter stays a circle — it's a thumb target, and a ring is
/// the honest shape for a count that wraps — but everything around it is ruled,
/// and the number itself is now set rather than rendered in rounded system.
struct DhikrView: View {
    @StateObject private var store = DhikrStore()
    @State private var showGoalEditor = false

    var body: some View {
        VStack(spacing: 0) {
            presetPicker
                .padding(.horizontal, 24)
                .padding(.top, 10)

            Spacer(minLength: 20)

            counterButton

            Spacer(minLength: 20)
        }
        // As a safe-area inset rather than the last row of the VStack, and with
        // the tab bar's height reserved by hand — the TabView's own inset does
        // not reach a fixed layout inside a pushed stack, so the bar was being
        // drawn underneath it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar.padding(.bottom, EditorialTabBar.barHeight)
        }
        .navigationTitle("Dhikr")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.tap(); showGoalEditor = true } label: {
                    Image(systemName: "target")
                }
                .accessibilityLabel("Set goal")
            }
        }
        .sheet(isPresented: $showGoalEditor) {
            GoalEditorSheet(goal: $store.customGoal) {
                store.reset()
            }
        }
    }

    // MARK: - Preset strip

    private var presetPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DhikrStore.defaultPresets) { preset in
                    let on = store.selectedPreset.id == preset.id
                    Button {
                        Haptics.selection()
                        withAnimation(AppAnim.smooth) { store.select(preset) }
                    } label: {
                        Text(preset.name.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(1.1)
                            .foregroundStyle(on ? Color.brand : Color(.label).opacity(0.5))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 8)
                            .overlay(
                                Rectangle().strokeBorder(on ? Color.brand : Color(.label).opacity(0.18),
                                                         lineWidth: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: - Counter

    private var counterButton: some View {
        ZStack {
            // Track + progress, both hairline-thin so the numeral carries the screen.
            Circle()
                .stroke(Color(.label).opacity(0.12), lineWidth: 2)
                .frame(width: 250, height: 250)

            Circle()
                .trim(from: 0, to: store.progress)
                .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .butt))
                .rotationEffect(.degrees(-90))
                .frame(width: 250, height: 250)
                .animation(.spring(duration: 0.3), value: store.progress)

            Button(action: store.tap) {
                VStack(spacing: 8) {
                    if store.goalReached {
                        Image(systemName: "checkmark")
                            .font(.system(size: 52, weight: .light))
                            .foregroundStyle(.brand)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Text("\(store.count)")
                            .font(.appSerif(72, weight: .light))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText(countsDown: false))
                            .animation(.spring(duration: 0.2), value: store.count)
                    }

                    Eyebrow(store.selectedPreset.name)
                }
                .frame(width: 230, height: 230)
                .contentShape(Circle())
            }
            .buttonStyle(TapScaleStyle())
            .disabled(store.goalReached)
            .accessibilityLabel("\(store.selectedPreset.name), \(store.count) of \(store.goal)")
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("Goal")
                    Text("\(store.count) / \(store.goal)")
                        .font(.appSerif(19, weight: .medium).monospacedDigit())
                        .foregroundStyle(store.goalReached ? Color.brand : Color(.label))
                }

                Spacer()

                if !store.sessionCounts.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow("Session")
                        Text("\(store.sessionCounts.values.reduce(0, +))")
                            .font(.appSerif(19, weight: .medium).monospacedDigit())
                    }
                    Spacer()
                }

                Button {
                    Haptics.tap()
                    store.reset()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("RESET")
                            .font(.system(size: 10, weight: .semibold))
                            .kerning(1.2)
                    }
                    .foregroundStyle(.brand)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .overlay(Rectangle().strokeBorder(Color.brand.opacity(0.5), lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Goal editor sheet

struct GoalEditorSheet: View {
    @Binding var goal: Int
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftGoal: Int = 33

    private let presets = [7, 10, 33, 34, 99, 100, 200, 500, 1000]
    private let columns = [GridItem(.adaptive(minimum: 62), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(draftGoal)")
                            .font(.appSerif(48, weight: .medium).monospacedDigit())
                            .contentTransition(.numericText())
                        Text("repetitions")
                            .font(.appSerif(16, italic: true))
                            .foregroundStyle(Color(.label).opacity(0.45))
                        Spacer(minLength: 0)
                        Stepper("", value: $draftGoal, in: 1...1000)
                            .labelsHidden()
                    }
                    .padding(.bottom, 22)

                    Eyebrow("Common counts").padding(.bottom, 12)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(presets, id: \.self) { n in
                            let on = draftGoal == n
                            Button {
                                Haptics.selection()
                                draftGoal = n
                            } label: {
                                Text("\(n)")
                                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(on ? Color.brand : Color(.label).opacity(0.55))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 11)
                                    .overlay(
                                        Rectangle().strokeBorder(on ? Color.brand : Color(.label).opacity(0.18),
                                                                 lineWidth: 1)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Footnote("You'll get a stronger vibration when you reach this count. Setting a goal restarts the counter.")
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 30)
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
