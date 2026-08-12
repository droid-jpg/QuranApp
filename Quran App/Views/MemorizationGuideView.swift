import SwiftUI

/// A full explainer for the memorization engine, presented as a sheet from the
/// hub's help button, its "How it works" link, and the first-run empty state.
/// It teaches the whole feature in one place — the mental model (mark vs.
/// review), how to add ayahs, the goals, how spaced-repetition review and
/// grading work, and the drill styles — so the engine is self-teaching rather
/// than something the user has to reverse-engineer.
struct MemorizationGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    hero
                    addingSection
                    goalsSection
                    reviewSection
                    gradesSection
                    drillSection
                    markingSection
                    tip
                }
                .padding(20)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 92, height: 92)
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(
                        LinearGradient(colors: [.brand, .brand.opacity(0.65)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
            Text("Memorize, the smart way")
                .font(.appSerif(23, weight: .medium))
                .multilineTextAlignment(.center)
            Text("Add ayahs you want to learn and the app schedules them with spaced repetition — resurfacing each one right before you'd forget, so it sticks with far less effort.")
                .font(.appSerif(15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    // MARK: Getting started

    private var addingSection: some View {
        GuideSection(title: "Adding ayahs", systemImage: "plus.circle.fill") {
            VStack(alignment: .leading, spacing: 16) {
                GuideStep(number: 1, title: "Open any surah",
                          detail: "Browse to a surah from the Quran tab and start reading.")
                GuideStep(number: 2, title: "Add what you want to learn",
                          detail: "Tap the + beside an ayah to enrol just that verse — or choose “Memorize Surah” from the ⋯ menu to add the whole surah at once.")
                GuideStep(number: 3, title: "Review here, daily",
                          detail: "Come back to this screen and tap Review. A few minutes a day is all it takes.")
            }
        }
    }

    // MARK: Goals

    private var goalsSection: some View {
        GuideSection(title: "Pick a goal", systemImage: "target") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tell the app what you're memorizing for and it tailors how each ayah is tested. You can change a surah's goal anytime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(MemorizationGoal.allCases) { goal in
                    GuideRow(icon: goal.icon, title: goal.title, detail: goal.caption)
                }
            }
        }
    }

    // MARK: How review works

    private var reviewSection: some View {
        GuideSection(title: "How review works", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Each ayah has its own schedule. When one is due, it appears in your review queue. Recall it, then rate how it went — the app stretches or shrinks the gap until the next review based on your answer.")
                    .font(.appSerif(15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.appSerif(19))
                        .foregroundStyle(.green)
                    Text("Once you've recalled an ayah comfortably for about three weeks, it's counted as **Mastered**.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tintedCard(.green)
            }
        }
    }

    // MARK: Grades

    private var gradesSection: some View {
        GuideSection(title: "Rating your recall", systemImage: "hand.thumbsup") {
            VStack(spacing: 10) {
                ForEach(ReviewGrade.allCases, id: \.self) { grade in
                    GuideGradeRow(grade: grade)
                }
            }
        }
    }

    // MARK: Drill styles

    private var drillSection: some View {
        GuideSection(title: "Three ways you're tested", systemImage: "rectangle.3.group") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your goal decides which of these show up. Each due ayah is drilled with one, picked at random to keep you on your toes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                GuideRow(icon: ReviewMode.flashcard.icon, title: ReviewMode.flashcard.title,
                         detail: "See the Arabic, recall what it means.")
                GuideRow(icon: ReviewMode.fillBlank.icon, title: ReviewMode.fillBlank.title,
                         detail: "A word is hidden — supply the missing piece.")
                GuideRow(icon: ReviewMode.audio.icon, title: ReviewMode.audio.title,
                         detail: "Hear the recitation, recite it back from memory.")
            }
        }
    }

    // MARK: Marking vs. reviewing

    private var markingSection: some View {
        GuideSection(title: "Marking vs. reviewing", systemImage: "square.grid.3x3.fill") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Two ways to track progress — use either or both:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ConceptCard(
                    icon: "hand.point.up.left.fill", tint: .orange,
                    title: "Mark a surah",
                    detail: "A quick self-assessment — flag a surah In Progress or Memorized. It paints the 114-surah progress grid, even for surahs you're not actively drilling. Set it from a surah's page in this hub."
                )
                ConceptCard(
                    icon: "graduationcap.fill", tint: .brand,
                    title: "Add to review",
                    detail: "Actively drills individual ayahs with spaced repetition and tracks true mastery. A surah turns green on the grid on its own once every ayah is mastered."
                )
            }
        }
    }

    // MARK: Tip

    private var tip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.appSerif(15))
                .foregroundStyle(.yellow)
            Text("Short and daily beats long and rare. Five honest minutes a day will out-memorize an hour once a week — the spacing is doing the heavy lifting.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedCard(.yellow)
    }
}

// MARK: - Building blocks

/// A titled block: a teal icon + headline, then arbitrary content beneath.
private struct GuideSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.bold())
                    .foregroundStyle(.brand)
                Text(title)
                    .font(.appSerif(17, weight: .semibold))
            }
            content
        }
    }
}

/// A numbered onboarding step.
private struct GuideStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color.brand, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// An icon-circle + title + caption row, used for goals and drill styles.
private struct GuideRow: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = .brand

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// One review-grade pill + what choosing it does to the schedule.
private struct GuideGradeRow: View {
    let grade: ReviewGrade

    var body: some View {
        HStack(spacing: 12) {
            Text(grade.label)
                .font(.caption.weight(.bold))
                .foregroundStyle(grade.tint)
                .frame(width: 58)
                .padding(.vertical, 7)
                .background(grade.tint.opacity(0.15), in: Rectangle())
            Text(grade.guideDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// A bordered concept card contrasting the two progress-tracking models.
private struct ConceptCard: View {
    let icon: String
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.14), in: Rectangle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tintedCard(tint)
    }
}

#Preview {
    MemorizationGuideView()
}
