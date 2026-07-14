import Foundation
import SwiftUI

/// Fake-but-realistic data for SwiftUI previews. Not used at runtime.
@MainActor
enum PreviewData {
    static func store() -> UsageStore {
        let store = UsageStore(preferences: PreferencesStore())

        store.apply(UsageSnapshot(
            provider: .claudeCode,
            health: .ok,
            session: SessionUsage(
                tokens: TokenUsage(input: 1_200, output: 45_000, cacheWrite: 850_000, cacheRead: 2_400_000),
                cost: CostEstimate(amountUSD: 21.37),
                startedAt: Date().addingTimeInterval(-2.5 * 3600),
                resetsAt: Date().addingTimeInterval(2.5 * 3600)
            ),
            weekly: WeeklyUsage(
                tokens: TokenUsage(input: 9_000, output: 310_000, cacheWrite: 5_200_000, cacheRead: 19_000_000),
                cost: CostEstimate(amountUSD: 148.20),
                dailyTotals: (0..<7).map { offset in
                    DailyTotal(
                        day: Date().addingTimeInterval(Double(-offset) * 86_400).flooredToDay,
                        tokens: [3_400_000, 1_100_000, 5_600_000, 2_300_000, 800_000, 4_100_000, 2_900_000][offset],
                        costUSD: 20
                    )
                }
            ),
            activeModel: "claude-fable-5",
            lastActivityAt: Date().addingTimeInterval(-240)
        ))

        store.apply(UsageSnapshot(
            provider: .codex,
            health: .ok,
            session: SessionUsage(
                tokens: TokenUsage(input: 12_000, output: 4_000, cacheRead: 4_500),
                cost: CostEstimate(amountUSD: 0.06),
                resetsAt: Date().addingTimeInterval(3.1 * 3600),
                usedPercent: 34
            ),
            weekly: WeeklyUsage(
                tokens: TokenUsage(input: 220_000, output: 84_000, cacheRead: 96_000),
                cost: CostEstimate(amountUSD: 1.18),
                usedPercent: 72,
                resetsAt: Date().addingTimeInterval(3.4 * 86_400)
            ),
            activeModel: "gpt-5",
            lastActivityAt: Date().addingTimeInterval(-3_600),
            note: "Plan: pro"
        ))

        store.apply(UsageSnapshot(
            provider: .geminiCLI,
            health: .noData,
            note: "Token data not exposed by Gemini CLI"
        ))

        store.updateSparkline(.claudeCode, values: [2, 5, 3, 8, 12, 7, 14, 9, 16, 11])
        return store
    }

    static func notchViewModel(expanded: Bool = false) -> NotchViewModel {
        let vm = NotchViewModel(geometry: NotchGeometry(
            hasNotch: true,
            notchWidth: 200,
            topInset: 38,
            screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982)
        ))
        if expanded {
            vm.togglePin()
        }
        return vm
    }
}

#Preview("Notch — compact") {
    NotchContainerView()
        .environment(PreviewData.store())
        .environment(PreviewData.notchViewModel())
        .environment(WindowRouter())
        .frame(width: NotchViewModel.canvasSize.width, height: 120, alignment: .top)
        .background(.blue.opacity(0.2))
}

#Preview("Notch — expanded") {
    NotchContainerView()
        .environment(PreviewData.store())
        .environment(PreviewData.notchViewModel(expanded: true))
        .environment(WindowRouter())
        .frame(width: NotchViewModel.canvasSize.width, height: NotchViewModel.canvasSize.height, alignment: .top)
        .background(.blue.opacity(0.2))
}

#Preview("Menu bar content") {
    MenuBarContentView()
        .environment(PreviewData.store())
        .environment(PreferencesStore())
        .environment(WindowRouter())
}

#Preview("Dashboard") {
    DashboardView()
        .environment(PreviewData.store())
        .environment(PreferencesStore())
        .environment(WindowRouter())
}
