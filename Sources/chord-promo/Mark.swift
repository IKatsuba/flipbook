import Flipbook
import SwiftUI

/// chord's mark in half cells, from its generated `src/ui/header/mark.ts`:
/// each filled half cell's place on the diagonal gradient, `nil` where empty.
enum MarkGrid {
    static let small: [[Double?]] = [
        [0.0745, nil, nil, nil],
        [0.171, 0.2234, nil, nil],
        [0.2674, 0.3199, 0.3723, nil],
        [nil, 0.4164, 0.4688, 0.5213],
        [nil, 0.5129, 0.5653, 0.6178],
        [0.5569, 0.6093, 0.6618, nil],
        [0.6534, 0.7058, nil, nil],
        [0.7498, nil, nil, nil],
    ]

    static let splash: [[Double?]] = [
        [0.0372, 0.0635, nil, nil, nil, nil, nil, nil, nil],
        [0.0855, 0.1117, 0.1379, nil, nil, nil, nil, nil, nil],
        [0.1337, 0.1599, 0.1862, 0.2124, nil, nil, nil, nil, nil],
        [0.182, 0.2082, 0.2344, 0.2606, 0.2869, nil, nil, nil, nil],
        [0.2302, 0.2564, 0.2827, 0.3089, 0.3351, 0.3613, nil, nil, nil],
        [0.2784, 0.3047, 0.3309, 0.3571, 0.3833, 0.4096, 0.4358, nil, nil],
        [nil, 0.3529, 0.3791, 0.4054, 0.4316, 0.4578, 0.484, 0.5103, nil],
        [nil, nil, 0.4274, 0.4536, 0.4798, 0.5061, 0.5323, 0.5585, 0.5847],
        [nil, nil, 0.4756, 0.5018, 0.5281, 0.5543, 0.5805, 0.6068, 0.633],
        [nil, 0.4976, 0.5239, 0.5501, 0.5763, 0.6025, 0.6288, 0.655, nil],
        [0.5196, 0.5459, 0.5721, 0.5983, 0.6246, 0.6508, 0.677, nil, nil],
        [0.5679, 0.5941, 0.6203, 0.6466, 0.6728, 0.699, nil, nil, nil],
        [0.6161, 0.6424, 0.6686, 0.6948, 0.721, nil, nil, nil, nil],
        [0.6644, 0.6906, 0.7168, 0.743, nil, nil, nil, nil, nil],
        [0.7126, 0.7388, 0.7651, nil, nil, nil, nil, nil, nil],
        [0.7608, 0.7871, nil, nil, nil, nil, nil, nil, nil],
    ]
}

/// The pixel mark. With a `frame`, its cells arrive along the gradient, top-left first.
struct Mark: View {
    var grid = MarkGrid.splash
    var cell = CGSize(width: 20, height: 20)
    var frame: Frame?

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, _ in
            for (row, cells) in grid.enumerated() {
                for (column, place) in cells.enumerated() {
                    guard let place else { continue }
                    let grow = frame.map { $0.spring(from: 8 + Int(place * 44), stiffness: 220, damping: 18) } ?? 1
                    guard grow > 0 else { continue }
                    let centre = CGPoint(x: (CGFloat(column) + 0.5) * cell.width, y: (CGFloat(row) + 0.5) * cell.height)
                    // Half a point of overlap, so neighbours leave no seam.
                    let size = CGSize(width: (cell.width + 0.5) * grow, height: (cell.height + 0.5) * grow)
                    let rect = CGRect(x: centre.x - size.width / 2, y: centre.y - size.height / 2, width: size.width, height: size.height)
                    context.fill(Path(rect), with: .color(Theme.mark(place)))
                }
            }
        }
        .frame(width: CGFloat(grid[0].count) * cell.width, height: CGFloat(grid.count) * cell.height)
    }
}

/// CHORD in block letters with a stepped shadow, as on chord's start page.
struct Wordmark: View {
    var unit: CGFloat = 32
    var frame: Frame?

    static let letters: [[String]] = [
        ["11111", "10000", "10000", "10000", "10000", "10000", "11111"],
        ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
        ["11111", "10001", "10001", "10001", "10001", "10001", "11111"],
        ["11111", "10001", "10001", "11111", "10010", "10001", "10001"],
        ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    ]

    var body: some View {
        HStack(spacing: unit) {
            ForEach(0..<Self.letters.count, id: \.self) { index in
                let arrive = frame.map { $0.spring(from: 34 + index * 5, stiffness: 170, damping: 15) } ?? 1
                ZStack(alignment: .topLeading) {
                    letter(Self.letters[index]).fill(Theme.hex(0x0A7470)).offset(x: unit * 0.22, y: unit * 0.22)
                    letter(Self.letters[index]).fill(Theme.hex(0x3FDC9C))
                }
                .frame(width: unit * 5, height: unit * 7, alignment: .topLeading)
                .offset(y: -unit * 2 * (1 - arrive))
                .opacity(frame.map { $0.interpolate([Double(34 + index * 5), Double(42 + index * 5)], [0, 1]) } ?? 1)
            }
        }
    }

    private func letter(_ rows: [String]) -> Path {
        var path = Path()
        for (row, cells) in rows.enumerated() {
            for (column, cell) in cells.enumerated() where cell == "1" {
                path.addRect(CGRect(x: CGFloat(column) * unit, y: CGFloat(row) * unit, width: unit + 0.5, height: unit + 0.5))
            }
        }
        return path
    }
}

/// The mark beside the wordmark.
struct Lockup: View {
    var unit: CGFloat = 32
    var frame: Frame?

    var body: some View {
        HStack(spacing: unit * 1.4) {
            Mark(cell: CGSize(width: unit * 0.62, height: unit * 0.62), frame: frame)
            Wordmark(unit: unit, frame: frame)
        }
    }
}
