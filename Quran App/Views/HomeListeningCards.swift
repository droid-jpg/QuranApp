import SwiftUI

// Today's one-tap starts. Now playing and resume live in the app-wide mini
// player (`MiniPlayer.swift`).

// MARK: - Quick-start row

/// One-tap starts for when there's no thread to resume: today's verse, the loop
/// that was last running, and the juz most people actually listen through.
struct QuickStartRail: View {
    let items: [QuickStart]

    struct QuickStart: Identifiable {
        let id: String
        let label: String
        /// SF Symbol; `nil` renders a text-only chip (e.g. "Juz 30").
        var icon: String? = nil
        var tint: Color? = nil
        let action: () -> Void
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    OutlineChip(label: item.label, icon: item.icon, tint: item.tint, action: item.action)
                }
            }
            .padding(.horizontal, 24)
        }
    }
}
