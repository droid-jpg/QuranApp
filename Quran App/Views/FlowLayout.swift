import SwiftUI

/// A simple wrapping flow layout. Fills each line left-to-right (or right-to-left
/// for Arabic) and wraps to the next line when the next subview won't fit.
/// RTL is handled explicitly here rather than via the environment, because a
/// custom Layout's `place(at:)` coordinates are not mirrored automatically.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 14
    var rightToLeft: Bool = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var widestRow: CGFloat = 0

        for size in sizes {
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + lineSpacing
                widestRow = max(widestRow, rowWidth)
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        totalHeight += rowHeight
        widestRow = max(widestRow, rowWidth)

        let width = proposal.width ?? widestRow
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }

        // Group subview indices into rows.
        var rows: [[Int]] = []
        var current: [Int] = []
        var rowWidth: CGFloat = 0
        for i in subviews.indices {
            let w = sizes[i].width
            if !current.isEmpty, rowWidth + spacing + w > maxWidth {
                rows.append(current); current = []; rowWidth = 0
            }
            rowWidth = current.isEmpty ? w : rowWidth + spacing + w
            current.append(i)
        }
        if !current.isEmpty { rows.append(current) }

        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            if rightToLeft {
                var x = bounds.maxX
                for i in row {
                    let s = sizes[i]
                    subviews[i].place(
                        at: CGPoint(x: x - s.width, y: y + (rowHeight - s.height) / 2),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(s)
                    )
                    x -= (s.width + spacing)
                }
            } else {
                var x = bounds.minX
                for i in row {
                    let s = sizes[i]
                    subviews[i].place(
                        at: CGPoint(x: x, y: y + (rowHeight - s.height) / 2),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(s)
                    )
                    x += (s.width + spacing)
                }
            }
            y += rowHeight + lineSpacing
        }
    }
}
