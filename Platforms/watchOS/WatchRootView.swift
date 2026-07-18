import AgentMeterCore
import SwiftUI

struct WatchRootView: View {
    @EnvironmentObject private var subscriptions: SubscriptionStore

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("AgentMeter")
                    .font(.headline)
                Text(watchBRL(subscriptions.summary.monthlyTotalBRL))
                    .font(.title3.bold())
                    .minimumScaleFactor(0.7)
                Text("por mês")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let renewal = subscriptions.subscriptions.first {
                    Divider()
                    VStack(spacing: 3) {
                        Text("Próxima renovação")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(renewal.provider.displayName)
                            .font(.headline)
                        Text(renewal.nextRenewalDate, style: .date)
                            .font(.caption)
                    }
                }

                Divider()
                if subscriptions.isCloudSyncEnabled {
                    Button {
                        Task { await subscriptions.syncNow() }
                    } label: {
                        Label("Sincronizar", systemImage: "arrow.clockwise.icloud")
                    }
                    .font(.caption)
                } else {
                    Button {
                        Task { await subscriptions.setCloudSyncEnabled(true) }
                    } label: {
                        Label("Usar iCloud", systemImage: "icloud")
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            await subscriptions.syncIfEnabled()
        }
    }
}

#Preview {
    WatchRootView()
        .environmentObject(SubscriptionStore())
}

private func watchBRL(_ value: Decimal) -> String {
    NSDecimalNumber(decimal: value).doubleValue.formatted(.currency(code: "BRL"))
}
