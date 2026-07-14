import SwiftUI

/// Chunky block meter, the stick's signature gauge. Filled blocks take the
/// state color; empty blocks stay as faint sockets.
struct SegmentedMeter: View {
    let percent: Double
    var segments: Int = 14
    var tint: Color = Theme.coral
    var height: CGFloat = 9
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(index < filledCount ? tint : Theme.socket)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.4), value: filledCount)
    }

    private var filledCount: Int {
        let clamped = min(max(percent, 0), 100)
        // Any usage at all lights the first block.
        let count = Int((clamped / 100 * Double(segments)).rounded())
        return clamped > 0 ? max(count, 1) : 0
    }
}
