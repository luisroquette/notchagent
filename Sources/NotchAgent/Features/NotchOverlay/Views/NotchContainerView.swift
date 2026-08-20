import SwiftUI

/// Root view inside the transparent overlay canvas. Draws the black notch
/// shape, swaps compact/expanded content, and drives hover expansion.
struct NotchContainerView: View {
    @Environment(NotchViewModel.self) private var viewModel
    @Environment(UsageStore.self) private var store
    @Environment(PreferencesStore.self) private var preferences
    @Environment(MascotMind.self) private var mind

    private var panelShape: NotchShape {
        NotchShape(
            bottomRadius: viewModel.isExpanded ? 22 : 10,
            topRadius: viewModel.geometry.hasNotch ? 0 : 12
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: viewModel.topOffset)

            ZStack(alignment: .top) {
                panelShape
                    .fill(viewModel.isExpanded ? Theme.panel : Color.black)
                    .shadow(color: .black.opacity(viewModel.isExpanded ? 0.45 : 0.2), radius: viewModel.isExpanded ? 14 : 4, y: 4)

                // Time-of-day wash: only when weather is OFF — with weather
                // on, the panel stays the uniform dark plate (minimal strip
                // at the top, no full-panel ambience).
                if TimeTintVisibleRule.evaluate(
                    delightEnabled: preferences.settings.delightEnabled,
                    weatherEnabled: preferences.settings.weatherEnabled
                ) {
                    TimelineView(.periodic(from: .now, by: 300)) { timeline in
                        TimeTintView(key: DelightSignals.timeTint(at: timeline.date))
                            .clipShape(panelShape)
                            .transition(.opacity)
                    }
                    .accessibilityHidden(true)
                }

                // REFACTOR 19/08/2026: the full-panel weather sky and
                // precipitation layers lived here (bright blue gradient +
                // large sun behind every card). Weather is now a minimal
                // 8-bit strip at the TOP of the panel (WeatherHeaderView) —
                // the panel background stays the uniform dark plate.
                content
            }
            .frame(width: viewModel.currentSize.width, height: viewModel.currentSize.height)
            .onHover { hovering in
                viewModel.hoverChanged(hovering)
            }
            .onTapGesture {
                // Clicking opens a temporary panel. Pinning is explicit via
                // the pin button; an ordinary click must never trap the panel.
                if !viewModel.isExpanded {
                    viewModel.forceExpand()
                }
            }
            .animation(.spring(duration: 0.38, bounce: 0.16), value: viewModel.isExpanded)
            .onChange(of: viewModel.isExpanded) { _, expanded in
                if expanded {
                    mind.noteExpanded()
                } else {
                    mind.noteCollapsed()
                }
            }

            Spacer(minLength: 0)
        }
        .frame(width: NotchViewModel.canvasSize.width, height: NotchViewModel.canvasSize.height, alignment: .top)
        .onExitCommand {
            _ = viewModel.handleEscape()
        }
        .onChange(of: store.activeThresholdAlert) { _, alert in
            // A threshold crossing takes over the panel, escalating with severity.
            viewModel.isAlertPresented = alert != nil
            if alert != nil {
                viewModel.forceExpand()
            } else if !viewModel.isPinned, !viewModel.isHovering, store.activeRestoreMoment == nil {
                // Auto-dismiss with the cursor away → tidy up; with the cursor
                // inside, stay expanded so the gauges replace the alert in place.
                viewModel.collapseNow()
            }
        }
        .onChange(of: store.activeRestoreMoment) { _, moment in
            viewModel.isAlertPresented = moment != nil || store.activeThresholdAlert != nil
            if moment != nil {
                viewModel.forceExpand()
            } else if !viewModel.isPinned, !viewModel.isHovering, store.activeThresholdAlert == nil {
                viewModel.collapseNow()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isExpanded {
            if let alert = store.activeThresholdAlert {
                // A live danger takeover always wins over a celebration.
                AlertMomentView(alert: alert) {
                    store.dismissThresholdAlert()
                }
                .padding(.horizontal, 14)
                .padding(.top, viewModel.geometry.hasNotch ? viewModel.geometry.topInset + 6 : 12)
                .padding(.bottom, 14)
            } else if let moment = store.activeRestoreMoment {
                RestoreMomentView(moment: moment) {
                    store.dismissRestoreMoment()
                }
                .padding(.horizontal, 14)
                .padding(.top, viewModel.geometry.hasNotch ? viewModel.geometry.topInset + 6 : 12)
                .padding(.bottom, 14)
            } else {
                NotchExpandedView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        } else {
            NotchCompactView()
                .frame(height: viewModel.compactSize.height)
                .transition(.opacity)
                // The compact bar blends with the black camera housing, so it
                // is always rendered with the dark palette, whatever the theme.
                .environment(\.colorScheme, .dark)
        }
    }
}
