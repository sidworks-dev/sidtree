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
    /// Lane colours: violet, teal and amber first (as in the design), then further distinct hues.
    static let colors: [NSColor] = [
        Theme.dynamic(0x7C3AED, 0x8B5CF6),  // violet
        Theme.dynamic(0x0F8A7A, 0x3FB9A8),  // teal
        Theme.dynamic(0xA16207, 0xE6B35A),  // amber
        Theme.dynamic(0x2563EB, 0x6FA3F7),  // blue
        Theme.dynamic(0xC0367A, 0xE879B0),  // pink
        Theme.dynamic(0x2F855A, 0x6FCF8E),  // green
        Theme.dynamic(0xC53030, 0xF08A8A),  // red
        Theme.dynamic(0x4F46E5, 0x9A94F5),  // indigo
        Theme.dynamic(0x0E7490, 0x5CC8E0),  // cyan
        Theme.dynamic(0x65A30D, 0xA3D45A)   // lime
    ]

    /// Readable label text for refs on a lane.
    static let labelColors: [NSColor] = [
        Theme.dynamic(0x6D28D9, 0xC4B5FD),
        Theme.dynamic(0x0F766E, 0x7FDCCD),
        Theme.dynamic(0x92400E, 0xF0CB85),
        Theme.dynamic(0x1D4ED8, 0xA9C7FB),
        Theme.dynamic(0x9D174D, 0xF5B3D3),
        Theme.dynamic(0x276749, 0xA6E3B8),
        Theme.dynamic(0x9B2C2C, 0xF6B3B3),
        Theme.dynamic(0x4338CA, 0xC4C1FA),
        Theme.dynamic(0x155E75, 0x9EDDEC),
        Theme.dynamic(0x4D7C0F, 0xC7E79A)
    ]

    private static func wrap(_ index: Int) -> Int { ((index % colors.count) + colors.count) % colors.count }
    static func color(_ index: Int) -> NSColor { colors[wrap(index)] }
    static func labelColor(_ index: Int) -> NSColor { labelColors[wrap(index)] }
}
