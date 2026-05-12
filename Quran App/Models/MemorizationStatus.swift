import SwiftUI

enum MemorizationStatus: String, Codable, CaseIterable {
    case notStarted, inProgress, memorized

    var label: String {
        switch self {
        case .notStarted: "Not Started"
        case .inProgress: "In Progress"
        case .memorized:  "Memorized"
        }
    }

    var icon: String {
        switch self {
        case .notStarted: "circle"
        case .inProgress: "circle.dotted.and.circle"
        case .memorized:  "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .notStarted: .secondary
        case .inProgress: .orange
        case .memorized:  .green
        }
    }

    var next: MemorizationStatus {
        switch self {
        case .notStarted: .inProgress
        case .inProgress: .memorized
        case .memorized:  .notStarted
        }
    }
}
