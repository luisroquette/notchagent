import SwiftUI

/// Compact status shown in the menu bar itself.
struct MenuBarLabelView: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
            if let text = summaryText {
                Text(text)
                    .monospacedDigit()
            }
        }
    }

    private var symbolName: String {
        switch store.overallAttention {
        case .normal: "speedometer"
        case .warning: "exclamationmark.triangle"
        case .critical: "exclamationmark.octagon"
        }
    }

    /// "% left" of the tightest-known window, Claude first.
    private var summaryText: String? {
        let snapshot = store.snapshots[.claudeCode] ?? store.primarySnapshot
        if let metric = GaugeMetric.from(snapshot) {
            return "\(Int(metric.remaining.rounded()))%"
        }
        if let tokens = snapshot?.session?.tokens.total, tokens > 0 {
            return Format.tokens(tokens)
        }
        return nil
    }
}
