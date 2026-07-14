import Charts
import SwiftUI

/// Full window: history charts, per-provider breakdown, event log with filters.
struct DashboardView: View {
    @Environment(UsageStore.self) private var store

    @State private var rangeHours = 24
    @State private var providerFilter: ProviderID?
    @State private var historyPoints: [HistoryStore.Point] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controls
                historyChart
                hourlyRhythm
                providerBreakdown
                eventLog
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 520)
        .task(id: rangeHours) {
            historyPoints = await AppEnvironment.shared.historyStore.allPoints(lastHours: rangeHours)
        }
    }

    private var controls: some View {
        HStack {
            Text("Dashboard")
                .font(.title2.bold())
            Spacer()
            Picker("Range", selection: $rangeHours) {
                Text("24h").tag(24)
                Text("7 days").tag(24 * 7)
                Text("30 days").tag(24 * 30)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            Picker("Provider", selection: $providerFilter) {
                Text("All").tag(ProviderID?.none)
                ForEach(ProviderID.allCases) { provider in
                    Text(provider.shortName).tag(ProviderID?.some(provider))
                }
            }
            .frame(width: 150)
        }
    }

    private var filteredPoints: [HistoryStore.Point] {
        providerFilter.map { filter in historyPoints.filter { $0.provider == filter } } ?? historyPoints
    }

    @ViewBuilder
    private var historyChart: some View {
        GroupBox("Session tokens over time") {
            if filteredPoints.isEmpty {
                emptyState("History builds up as NotchAgent keeps running.")
            } else {
                Chart(filteredPoints, id: \.hour) { point in
                    LineMark(
                        x: .value("Hour", point.hour),
                        y: .value("Tokens", point.sessionTokens),
                        series: .value("Provider", point.provider.shortName)
                    )
                    .foregroundStyle(by: .value("Provider", point.provider.shortName))
                    .interpolationMethod(.monotone)
                }
                .chartYAxisLabel("tokens")
                .frame(height: 200)
                .padding(.top, 6)
            }
        }
    }

    @State private var rhythmToday = false

    /// 24-bar "hourly rhythm": which hours of the day burn the most tokens,
    /// built from the providers' per-hour activity over the trailing week.
    private var hourlyRhythm: some View {
        GroupBox("Hourly rhythm") {
            let bars = rhythmBars
            if bars.allSatisfy({ $0.tokens == 0 }) {
                emptyState("No hourly activity recorded yet.")
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    Picker("", selection: $rhythmToday) {
                        Text("7 days").tag(false)
                        Text("Today").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    Chart(bars, id: \.hourOfDay) { bar in
                        BarMark(
                            x: .value("Hour", bar.hourOfDay),
                            y: .value("Tokens", bar.tokens)
                        )
                        .foregroundStyle(
                            bar.hourOfDay == Calendar.current.component(.hour, from: Date())
                                ? Color.accentColor
                                : Color.secondary.opacity(0.55)
                        )
                    }
                    .chartXScale(domain: 0...23)
                    .chartYAxis(.hidden)
                    .frame(height: 110)
                }
                .padding(.top, 4)
            }
        }
    }

    private var rhythmBars: [(hourOfDay: Int, tokens: Int)] {
        var totals = [Int](repeating: 0, count: 24)
        let dayStart = Date().flooredToDay
        for snapshot in store.snapshots.values {
            guard providerFilter == nil || snapshot.provider == providerFilter else { continue }
            for entry in snapshot.weekly?.hourlyTotals ?? [] {
                if rhythmToday && entry.hour < dayStart { continue }
                totals[Calendar.current.component(.hour, from: entry.hour)] += entry.tokens
            }
        }
        return totals.enumerated().map { (hourOfDay: $0.offset, tokens: $0.element) }
    }

    private var providerBreakdown: some View {
        GroupBox("Providers") {
            VStack(spacing: 0) {
                ForEach(ProviderID.allCases) { provider in
                    providerDetailRow(provider)
                    if provider != ProviderID.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    private func providerDetailRow(_ provider: ProviderID) -> some View {
        let snapshot = store.snapshots[provider]
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: provider.symbolName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(provider.displayName)
                        .font(.headline)
                    AttentionDot(level: store.attention(for: provider))
                }
                if let model = snapshot?.activeModel {
                    Text(model)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let note = snapshot?.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let activity = snapshot?.lastActivityAt {
                    Text("Last activity \(Format.relative(activity))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 260, alignment: .leading)

            statColumn("Session left", sessionStat(snapshot))
            statColumn("Week left", weeklyStat(snapshot))
            statColumn("Est. cost (7d)", costStat(snapshot))

            Spacer()

            if let daily = snapshot?.weekly?.dailyTotals, !daily.isEmpty {
                Chart(daily) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Tokens", day.tokens)
                    )
                    .foregroundStyle(.secondary.opacity(0.7))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(width: 140, height: 44)
            }
        }
        .padding(.vertical, 10)
    }

    private func statColumn(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 120, alignment: .leading)
    }

    private func sessionStat(_ snapshot: UsageSnapshot?) -> String {
        guard let session = snapshot?.session else { return "—" }
        if let percent = session.usedPercent {
            var text = "\(Int((100 - percent).rounded()))%"
            if let resets = session.resetsAt {
                text += " · \(Format.countdown(to: resets))"
            }
            return text
        }
        return session.tokens.total > 0 ? Format.tokens(session.tokens.total) : "idle"
    }

    private func weeklyStat(_ snapshot: UsageSnapshot?) -> String {
        guard let weekly = snapshot?.weekly else { return "—" }
        if let percent = weekly.usedPercent {
            var text = "\(Int((100 - percent).rounded()))%"
            if let resets = weekly.resetsAt {
                text += " · \(Format.countdown(to: resets))"
            }
            return text
        }
        return weekly.tokens.total > 0 ? Format.tokens(weekly.tokens.total) : "—"
    }

    private func costStat(_ snapshot: UsageSnapshot?) -> String {
        guard let cost = snapshot?.weekly?.cost else { return "—" }
        return "~" + Format.usd(cost.amountUSD)
    }

    private var eventLog: some View {
        GroupBox("Events") {
            if store.events.isEmpty {
                emptyState("No events yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(filteredEvents.prefix(30)) { event in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(event.level.color.opacity(0.85))
                                .frame(width: 6, height: 6)
                            Text(event.provider?.shortName ?? "App")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 50, alignment: .leading)
                            Text(event.message)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(Format.relative(event.date))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private var filteredEvents: [UsageEvent] {
        providerFilter.map { filter in store.events.filter { $0.provider == filter } } ?? store.events
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}
