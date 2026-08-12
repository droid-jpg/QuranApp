import SwiftUI

/// The Beautiful Names as a ruled register: a numeral in the margin, the
/// transliteration and meaning in serif, the Arabic set right. Tapping a line
/// marks it memorized.
struct NamesOfAllahView: View {
    @EnvironmentObject private var store: NamesStore
    @State private var searchText = ""
    @State private var filterStatus: NamesStore.NameStatus? = nil
    @State private var showFlashcards = false

    private var filtered: [AllahName] {
        AllahName.all.filter { name in
            let matchesSearch = searchText.isEmpty
                || name.transliteration.localizedCaseInsensitiveContains(searchText)
                || name.meaning.localizedCaseInsensitiveContains(searchText)
                || name.arabic.contains(searchText)
            let matchesFilter = filterStatus == nil || store.status(for: name.id) == filterStatus
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Progress
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(store.memorizedCount)")
                        .font(.appSerif(40, weight: .medium))
                        .contentTransition(.numericText())
                    Text("of 99 memorized")
                        .font(.appSerif(16, italic: true))
                        .foregroundStyle(Color(.label).opacity(0.45))
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 13)

                RuleProgress(fraction: Double(store.memorizedCount) / 99, tint: .brand)
                    .padding(.bottom, 18)

                // Filters
                HStack(spacing: 8) {
                    filterChip("All", on: filterStatus == nil) { filterStatus = nil }
                    filterChip("Memorized", on: filterStatus == .memorized) {
                        filterStatus = filterStatus == .memorized ? nil : .memorized
                    }
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 20)

                // Register
                VStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, name in
                        if index > 0 { Hairline(opacity: 0.6) }
                        NameRow(name: name, status: store.status(for: name.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.selection()
                                store.cycle(for: name.id)
                            }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .navigationTitle("99 Names")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Search name or meaning…")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.tap(); showFlashcards = true } label: {
                    Image(systemName: "rectangle.on.rectangle.angled")
                }
                .accessibilityLabel("Flashcards")
            }
        }
        .sheet(isPresented: $showFlashcards) {
            NamesFlashcardView().environmentObject(store)
        }
    }

    private func filterChip(_ label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(on ? Color.brand : Color(.label).opacity(0.5))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .overlay(
                    Rectangle().strokeBorder(on ? Color.brand : Color(.label).opacity(0.18), lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Name row

private struct NameRow: View {
    let name: AllahName
    let status: NamesStore.NameStatus

    private var isMemorized: Bool { status == .memorized }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(name.id)")
                .font(.system(size: 11, weight: .bold).monospacedDigit())
                .foregroundStyle(isMemorized ? Color.brand : Color(.label).opacity(0.3))
                .frame(minWidth: 22, alignment: .leading)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(name.transliteration)
                    .font(.appSerif(18, weight: .medium))
                    .foregroundStyle(Color(.label))
                Text(name.meaning)
                    .font(.appSerif(14, italic: true))
                    .foregroundStyle(Color(.label).opacity(0.45))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(name.arabic)
                    .font(.appArabic(21))
                    .environment(\.layoutDirection, .rightToLeft)
                HStack(spacing: 10) {
                    AudioSpeakButton(text: name.arabic, size: 13)
                    Image(systemName: isMemorized ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13))
                        .foregroundStyle(isMemorized ? Color.brand : Color(.label).opacity(0.22))
                }
            }
        }
        .padding(.vertical, 13)
        .animation(.easeInOut(duration: 0.2), value: status)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isMemorized ? [.isSelected] : [])
    }
}

#Preview {
    NavigationStack {
        NamesOfAllahView()
    }
    .environmentObject(NamesStore())
}
