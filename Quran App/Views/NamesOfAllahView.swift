import SwiftUI

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
        NavigationStack {
            VStack(spacing: 0) {
                // Progress header
                NamesProgressHeader(store: store)

                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        FilterChip(label: "All",       isSelected: filterStatus == nil)   { filterStatus = nil }
                        FilterChip(label: "Learning",  isSelected: filterStatus == .learning,
                                   color: .orange) { filterStatus = filterStatus == .learning ? nil : .learning }
                        FilterChip(label: "Memorized", isSelected: filterStatus == .memorized,
                                   color: .teal)   { filterStatus = filterStatus == .memorized ? nil : .memorized }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }

                List(filtered) { name in
                    NameRow(name: name, status: store.status(for: name.id))
                        .onTapGesture { store.cycle(for: name.id) }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
            }
            .navigationTitle("99 Names of Allah")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search name or meaning…")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showFlashcards = true } label: {
                        Label("Flashcards", systemImage: "rectangle.on.rectangle.angled")
                    }
                }
            }
            .sheet(isPresented: $showFlashcards) {
                NamesFlashcardView().environmentObject(store)
            }
        }
    }
}

// MARK: - Progress header

private struct NamesProgressHeader: View {
    @ObservedObject var store: NamesStore

    var body: some View {
        HStack(spacing: 0) {
            StatBlock(value: store.memorizedCount, label: "Memorized", color: .teal)
            Divider().frame(height: 36)
            StatBlock(value: store.learningCount,  label: "Learning",  color: .orange)
            Divider().frame(height: 36)
            StatBlock(value: 99 - store.memorizedCount - store.learningCount,
                      label: "Remaining", color: .secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }
}

private struct StatBlock: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    var color: Color = .teal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? color.opacity(0.15) : Color(.tertiarySystemBackground))
                .foregroundStyle(isSelected ? color : .secondary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? color : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Name row

private struct NameRow: View {
    let name: AllahName
    let status: NamesStore.NameStatus

    var body: some View {
        HStack(spacing: 14) {
            // Number badge
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                Text("\(name.id)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 34, height: 34)

            // Text block
            VStack(alignment: .leading, spacing: 2) {
                Text(name.transliteration)
                    .font(.body.bold())
                Text(name.meaning)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Arabic name
            Text(name.arabic)
                .font(.system(size: 20))
                .environment(\.layoutDirection, .rightToLeft)
                .foregroundStyle(.primary)

            AudioSpeakButton(text: name.arabic)
                .font(.body)

            // Status indicator
            Image(systemName: statusIcon)
                .font(.subheadline)
                .foregroundStyle(statusColor)
                .frame(width: 20)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(status == .notStarted ? Color.clear : statusColor.opacity(0.05))
        )
        .animation(.easeInOut(duration: 0.2), value: status)
        .contentShape(Rectangle())
    }

    private var statusColor: Color {
        switch status {
        case .notStarted: return .teal
        case .learning:   return .orange
        case .memorized:  return .teal
        }
    }

    private var statusIcon: String {
        switch status {
        case .notStarted: return "circle"
        case .learning:   return "circle.dotted.and.circle"
        case .memorized:  return "checkmark.circle.fill"
        }
    }
}

#Preview {
    NamesOfAllahView()
        .environmentObject(NamesStore())
}
