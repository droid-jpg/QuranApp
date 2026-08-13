import SwiftUI
import UIKit
import Combine

// The app's own action menu. `.contextMenu` and `Menu` both draw UIKit's rounded,
// blurred, SF-set popover — the one piece of iOS chrome the restyle could not
// reach. This is the ruled equivalent: a panel that rises from the bottom edge,
// titled with an eyebrow, its actions set in the reading serif and separated by
// hairlines rather than stacked in a floating card.

/// One row of an `EditorialMenu`.
struct EditorialAction: Identifiable {
    enum Kind {
        case normal
        /// Drawn in the accent — the action the menu exists for.
        case accent
        case destructive
    }

    let id = UUID()
    let title: String
    let icon: String
    var kind: Kind = .normal
    /// Trailing note, e.g. "3 due".
    var detail: String? = nil
    var isEnabled: Bool = true
    /// `nil` for rows that carry their own behaviour (share).
    var handler: (() -> Void)? = nil
    /// Text handed to a `ShareLink` instead of a tap handler.
    var shareText: String? = nil

    init(_ title: String, icon: String, kind: Kind = .normal, detail: String? = nil,
         isEnabled: Bool = true, handler: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.kind = kind
        self.detail = detail
        self.isEnabled = isEnabled
        self.handler = handler
    }

    /// A row that shares `text` through the system share sheet.
    init(share title: String, icon: String, text: String) {
        self.title = title
        self.icon = icon
        self.shareText = text
    }
}

/// Everything a menu needs to draw itself. Built at press time and handed to the
/// presenter, so the closures inside are never stale.
struct EditorialMenuRequest: Identifiable {
    let id = UUID()
    /// Small-caps line above the panel's subject, e.g. "Al-Baqarah · Ayah 14".
    var eyebrow: String? = nil
    /// Scripture preview — the ayah the menu belongs to, one line, elided.
    var arabic: String? = nil
    var translation: String? = nil
    /// Rows, grouped; groups are separated by a heavier gap and a rule.
    var groups: [[EditorialAction]]
}

// MARK: - Presenter

/// Holds whatever menu is open. The reader keeps one of these so the panel can be
/// drawn above *everything* — the pager, the top bar, the player — rather than
/// inside the page that raised it.
@MainActor
final class EditorialMenuPresenter: ObservableObject {
    @Published var request: EditorialMenuRequest?

    func present(_ request: EditorialMenuRequest) {
        Haptics.impact(.medium)
        withAnimation(AppAnim.springFast) { self.request = request }
    }

    func dismiss() {
        withAnimation(AppAnim.springFast) { request = nil }
    }
}

// MARK: - Panel

/// Scrim + panel. Present it as an overlay over the whole screen.
struct EditorialMenuOverlay: View {
    let request: EditorialMenuRequest
    let onDismiss: () -> Void

    private var type = ReadingType()

    init(request: EditorialMenuRequest, onDismiss: @escaping () -> Void) {
        self.request = request
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.38))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }
                .transition(.opacity)

            panel
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            ForEach(Array(request.groups.enumerated()), id: \.offset) { idx, group in
                if idx > 0 {
                    Rectangle()
                        .fill(Color.rule)
                        .frame(height: 6)
                        .opacity(0.5)
                }
                ForEach(Array(group.enumerated()), id: \.element.id) { rowIdx, action in
                    if rowIdx > 0 || idx > 0 { Hairline() }
                    row(action)
                }
            }
        }
        // The home-indicator allowance goes inside the background, or the panel
        // leaves a strip of dimmed page below itself.
        .padding(.bottom, safeBottom)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) { Hairline() }
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private var header: some View {
        if request.eyebrow != nil || request.arabic != nil || request.translation != nil {
            VStack(alignment: .leading, spacing: 8) {
                if let eyebrow = request.eyebrow {
                    Eyebrow(eyebrow, tint: .brand)
                }
                if let arabic = request.arabic {
                    Text(arabic)
                        .font(type.arabic(20))
                        .foregroundStyle(Color(.label).opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.head)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .environment(\.layoutDirection, .rightToLeft)
                }
                if let translation = request.translation {
                    Text(translation)
                        .font(type.serif(14))
                        .foregroundStyle(Color(.label).opacity(0.5))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 18)
        }
    }

    private func row(_ action: EditorialAction) -> some View {
        Group {
            if let text = action.shareText {
                ShareLink(item: text) { rowLabel(action) }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { onDismiss() })
            } else {
                Button {
                    onDismiss()
                    Haptics.tap()
                    action.handler?()
                } label: { rowLabel(action) }
                    .buttonStyle(.plain)
                    .disabled(!action.isEnabled)
            }
        }
    }

    private func rowLabel(_ action: EditorialAction) -> some View {
        HStack(spacing: 14) {
            Image(systemName: action.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint(action))
                .frame(width: 22)
            Text(action.title)
                .font(type.serif(17))
                .foregroundStyle(action.kind == .destructive ? Color.red : Color(.label))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            if let detail = action.detail {
                MetaText(detail.uppercased(), tint: .brand, size: 9.5)
            }
        }
        .opacity(action.isEnabled ? 1 : 0.35)
        .padding(.horizontal, 22)
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }

    private func tint(_ action: EditorialAction) -> Color {
        switch action.kind {
        case .normal:      Color(.label).opacity(0.55)
        case .accent:      Color.brand
        case .destructive: Color.red
        }
    }

    private var safeBottom: CGFloat {
        let inset = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first { $0.isKeyWindow }?.safeAreaInsets.bottom ?? 0
        return max(inset, 16)
    }
}

// MARK: - Presentation

extension View {
    /// Draws whatever menu the presenter is holding above this view.
    func editorialMenu(_ presenter: EditorialMenuPresenter) -> some View {
        overlay {
            if let request = presenter.request {
                EditorialMenuOverlay(request: request) { presenter.dismiss() }
                    .zIndex(20)
            }
        }
    }
}
