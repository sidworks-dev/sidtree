import AppKit

struct GraphLine: Hashable {
    let from: Int
    let to: Int
    let color: Int
    /// true: from the top edge of the row to its centre; false: from the centre to the bottom edge.
    let upper: Bool
}

struct GraphRow {
    var node: Int = 0
    var color: Int = 0
    var lines: [GraphLine] = []
    var width: Int = 1   // number of lanes used by this row
}

enum GraphLayout {
    /// Lane assignment in a single pass, in the order git emitted the commits.
    static func layout(_ commits: [Commit]) -> [GraphRow] {
        var lanes: [String?] = []
        var laneColors: [Int] = []
        var nextColor = 0
        var rows: [GraphRow] = []
        rows.reserveCapacity(commits.count)

        func allocate(_ hash: String, avoiding: Int = -1) -> Int {
            if let free = lanes.indices.first(where: { lanes[$0] == nil && $0 != avoiding }) {
                lanes[free] = hash
                laneColors[free] = nextColor
                nextColor += 1
                return free
            }
            lanes.append(hash)
            laneColors.append(nextColor)
            nextColor += 1
            return lanes.count - 1
        }

        for commit in commits {
            var row = GraphRow()
            var matching: [Int] = []
            for (i, h) in lanes.enumerated() where h == commit.id { matching.append(i) }

            let node: Int
            if let first = matching.first {
                node = first
            } else {
                node = allocate(commit.id)
            }
            row.node = node
            row.color = laneColors[node]

            // Top half: everything flowing into this row.
            for (i, h) in lanes.enumerated() {
                guard let h else { continue }
                if h == commit.id {
                    if !matching.isEmpty { row.lines.append(GraphLine(from: i, to: node, color: laneColors[i], upper: true)) }
                } else {
                    row.lines.append(GraphLine(from: i, to: i, color: laneColors[i], upper: true))
                }
            }

            // Update lane state.
            for i in matching.dropFirst() { lanes[i] = nil }
            var joined = Set<Int>()   // existing lanes a merge parent joins into
            var fresh = Set<Int>()    // lanes opened for a merge parent in this row
            if commit.parents.isEmpty {
                lanes[node] = nil
            } else {
                lanes[node] = commit.parents[0]
                for parent in commit.parents.dropFirst() {
                    if let existing = lanes.indices.first(where: { lanes[$0] == parent }) {
                        if existing != node { joined.insert(existing) }
                    } else {
                        fresh.insert(allocate(parent, avoiding: node))
                    }
                }
            }

            // Bottom half: everything flowing out of this row.
            for (i, h) in lanes.enumerated() where h != nil {
                if i == node {
                    row.lines.append(GraphLine(from: node, to: node, color: laneColors[node], upper: false))
                } else if fresh.contains(i) {
                    row.lines.append(GraphLine(from: node, to: i, color: laneColors[i], upper: false))
                } else {
                    row.lines.append(GraphLine(from: i, to: i, color: laneColors[i], upper: false))
                    if joined.contains(i) {
                        row.lines.append(GraphLine(from: node, to: i, color: laneColors[i], upper: false))
                    }
                }
            }

            while let last = lanes.last, last == nil {
                lanes.removeLast()
                laneColors.removeLast()
            }

            var width = node + 1
            for l in row.lines { width = max(width, l.from + 1, l.to + 1) }
            row.width = width
            rows.append(row)
        }
        return rows
    }
}

enum GraphPalette {
    static let colors: [NSColor] = [
        NSColor(srgbRed: 0.10, green: 0.53, blue: 0.98, alpha: 1),  // blue
        NSColor(srgbRed: 0.98, green: 0.55, blue: 0.10, alpha: 1),  // orange
        NSColor(srgbRed: 0.90, green: 0.24, blue: 0.20, alpha: 1),  // red
        NSColor(srgbRed: 0.20, green: 0.72, blue: 0.45, alpha: 1),  // green
        NSColor(srgbRed: 0.54, green: 0.27, blue: 0.98, alpha: 1),  // sidworks purple
        NSColor(srgbRed: 0.10, green: 0.74, blue: 0.80, alpha: 1),  // teal
        NSColor(srgbRed: 0.94, green: 0.36, blue: 0.66, alpha: 1),  // pink
        NSColor(srgbRed: 0.85, green: 0.70, blue: 0.10, alpha: 1),  // yellow
        NSColor(srgbRed: 0.40, green: 0.48, blue: 0.95, alpha: 1),  // indigo
        NSColor(srgbRed: 0.55, green: 0.75, blue: 0.20, alpha: 1)  // lime
    ]

    static func color(_ index: Int) -> NSColor { colors[((index % colors.count) + colors.count) % colors.count] }
}
