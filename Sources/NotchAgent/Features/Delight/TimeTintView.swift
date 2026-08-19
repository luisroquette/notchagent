import SwiftUI

/// Pure visibility rule for the time-of-day wash — weather wins; without
/// weather, the wash only shows when the delight layer is on.
public enum TimeTintVisibleRule {
    public static func evaluate(delightEnabled: Bool, weatherEnabled: Bool) -> Bool {
        delightEnabled && !weatherEnabled
    }
}

/// Subtle time-of-day wash over the panel, behind everything: cold at
/// night, warm at dusk. Never draws when the weather sky is on.
public struct TimeTintView: View {
    public let key: DelightSignals.TimeTintKey

    public init(key: DelightSignals.TimeTintKey) {
        self.key = key
    }

    public var body: some View {
        LinearGradient(
            colors: [Color(nsColor: DelightSignals.tintColor(for: key)), .clear],
            startPoint: .top,
            endPoint: .center
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
