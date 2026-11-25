import AppKit
import SwiftUI

/// Two panes separated by a draggable gap; the split fraction is persisted by the caller.
struct SplitPane<A: View, B: View>: View {
    let axis: Axis
    @Binding var fraction: Double
    var minFirst: CGFloat = 120
    var minSecond: CGFloat = 120
    /// Upper bound for the first pane, e.g. the height of its content.
    var maxFirst: CGFloat = .infinity
    /// Upper bound for the second pane: the first pane grows to leave no more than this.
    var maxSecond: CGFloat = .infinity
    var gap: CGFloat = 12
    /// Draws a 1pt border line as the separator (with a wider invisible grab area).
    var divider = false
    @ViewBuilder var first: A
    @ViewBuilder var second: B

    @State private var dragStart: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let gap = divider ? 1 : self.gap
            let total = axis == .vertical ? geo.size.height : geo.size.width
            let available = max(total - gap, 1)
            let upper = max(minFirst, min(available - minSecond, maxFirst))
            let lower = min(max(minFirst, available - maxSecond), upper)
            let firstSize = min(max(available * fraction, lower), upper)

            let grab = Color.clear
                .frame(width: axis == .horizontal ? max(gap, 8) : nil, height: axis == .vertical ? max(gap, 8) : nil)
                .contentShape(Rectangle())
                .overlay {
                    if !divider {
                        Capsule().fill(Theme.border)
                            .frame(width: axis == .horizontal ? 3 : 28, height: axis == .vertical ? 3 : 28)
                            .opacity(dragStart == nil ? 0.0 : 1)
                    }
                }
                .onHover { inside in
                    if inside {
                        (axis == .vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if dragStart == nil { dragStart = firstSize }
                            let delta = axis == .vertical ? value.translation.height : value.translation.width
                            let newSize = min(max((dragStart ?? firstSize) + delta, lower), upper)
                            fraction = Double(newSize / available)
                        }
                        .onEnded { _ in dragStart = nil }
                )
            let handle = (divider ? Theme.border : Color.clear)
                .frame(width: axis == .horizontal ? gap : nil, height: axis == .vertical ? gap : nil)
                .overlay { grab }
                .zIndex(1)

            if axis == .vertical {
                VStack(spacing: 0) {
                    first.frame(height: firstSize)
                    handle
                    second.frame(maxHeight: .infinity)
                }
            } else {
                HStack(spacing: 0) {
                    first.frame(width: firstSize)
                    handle
                    second.frame(maxWidth: .infinity)
                }
            }
        }
    }
}
