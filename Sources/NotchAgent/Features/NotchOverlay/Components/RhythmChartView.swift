import SwiftUI

/// 24-bar hourly rhythm: coral bars scaled by activity, current hour in white —
/// the stick's Ritmo por hora, rendered natively.
struct RhythmChartView: View {
    /// tokens per hour-of-day (index 0–23).
    let totals: [Int]

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                bars(in: proxy.size)
            }
            HStack {
                ForEach([0, 6, 12, 18, 23], id: \.self) { hour in
                    GaugeLabel(text: "\(hour)h", color: Theme.textFaint, size: 8)
                    if hour != 23 { Spacer() }
                }
            }
        }
    }

    private func bars(in size: CGSize) -> some View {
        let maxValue = max(totals.max() ?? 1, 1)
        let currentHour = Calendar.current.component(.hour, from: Date())
        let slot = size.width / 24

        return HStack(alignment: .bottom, spacing: slot * 0.28) {
            ForEach(0..<24, id: \.self) { hour in
                let ratio = Double(totals[hour]) / Double(maxValue)
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(barColor(hour: hour, currentHour: currentHour, ratio: ratio))
                    .frame(height: max(3, size.height * ratio))
                    .frame(maxWidth: .infinity, alignment: .bottom)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .bottom)
    }

    private func barColor(hour: Int, currentHour: Int, ratio: Double) -> Color {
        if hour == currentHour {
            return Theme.marker
        }
        if ratio <= 0 {
            return Theme.socket
        }
        // Busier hours glow hotter, like the stick's heat-scaled bars.
        return Theme.coral.opacity(0.35 + ratio * 0.65)
    }
}

/// Clickable carousel dots; the active page is a coral pill.
struct PagerDots: View {
    @Binding var page: Int
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    page = index
                } label: {
                    Capsule()
                        .fill(index == page ? Theme.coral : Theme.socket)
                        .frame(width: index == page ? 18 : 7, height: 7)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.spring(duration: 0.3), value: page)
    }
}
