import SwiftUI

// MARK: - Memorize whole surah (goal chooser)

/// Enroll an entire surah in spaced repetition with a chosen memorization goal.
/// Existing cards keep their schedule; only their goal is updated.
struct MemorizeSurahSheet: View {
    let surah: Surah
    let ayahs: [Ayah]
    /// Called after the user enrolls/updates the surah, before the sheet dismisses.
    var onEnrolled: () -> Void = {}

    @EnvironmentObject private var srStore: MemorizationSRStore
    @EnvironmentObject private var memorizationStore: MemorizationStore
    @Environment(\.dismiss) private var dismiss

    @State private var goal: MemorizationGoal = .both

    private var enrolledCount: Int { srStore.scheduledAyahs(inSurah: surah.number).count }
    private var allEnrolled: Bool { !ayahs.isEmpty && enrolledCount >= ayahs.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text(surah.englishName)
                            .font(.appSerif(24, weight: .medium))
                        Text("\(ayahs.count) ayahs"
                             + (enrolledCount > 0 ? " · \(enrolledCount) already in review" : ""))
                            .font(.appSerif(14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    Text("Adds every ayah to spaced-repetition review, so a few resurface for you to recall each day until the whole surah sticks.")
                        .font(.appSerif(13, italic: true))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("What are you memorizing for?")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(MemorizationGoal.allCases) { g in
                            GoalOptionRow(goal: g, selected: g == goal) {
                                Haptics.selection()
                                withAnimation(Motion.quick) { goal = g }
                            }
                        }
                    }

                    Button {
                        let seeds = ayahs.map {
                            MemorizationSRStore.AyahSeed(
                                ayah: $0.numberInSurah, arabic: $0.arabic,
                                translation: $0.translation, transliteration: $0.transliteration
                            )
                        }
                        srStore.enrollSurah(surah: surah.number, surahName: surah.englishName,
                                            ayahs: seeds, goal: goal)
                        if memorizationStore.manualStatus(for: surah.number) == .notStarted {
                            memorizationStore.set(.inProgress, for: surah.number)
                        }
                        Haptics.success()
                        onEnrolled()
                        dismiss()
                    } label: {
                        Text(allEnrolled ? "Update goal for all ayahs" : "Memorize all \(ayahs.count) ayahs")
                            .font(.headline)
                            .foregroundStyle(Color(.systemBackground))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Color.brand)
                            .clipShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(ayahs.isEmpty)

                    if enrolledCount > 0 {
                        Button(role: .destructive) {
                            Haptics.warning()
                            srStore.removeSurah(surah.number)
                            dismiss()
                        } label: {
                            Text("Remove surah from memorization")
                                .font(.appSerif(15))
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Memorize Surah")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .onAppear { goal = srStore.goal(forSurah: surah.number) ?? .both }
    }
}

private struct GoalOptionRow: View {
    let goal: MemorizationGoal
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: goal.icon)
                    .font(.label(16))
                    .foregroundStyle(selected ? Color.brand : Color.secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title)
                        .font(.appSerif(17))
                        .foregroundStyle(.primary)
                    Text(goal.caption)
                        .font(.appSerif(13, italic: true))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if selected {
                    Image(systemName: "checkmark")
                        .font(.label(13, weight: .bold))
                        .foregroundStyle(.brand)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .overlay(
                Rectangle()
                    .strokeBorder(selected ? Color.brand : Color(.label).opacity(0.18),
                                  lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
