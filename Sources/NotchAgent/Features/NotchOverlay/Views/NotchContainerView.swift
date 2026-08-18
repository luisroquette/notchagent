import SwiftUI

/// Root view inside the transparent overlay canvas. Draws the black notch
/// shape, swaps compact/expanded content, and drives hover expansion.
struct NotchContainerView: View {
    @Environment(NotchViewModel.self) private var viewModel
    @Environment(UsageStore.self) private var store
    @Environment(WeatherStore.self) private var weather
    @Environment(PreferencesStore.self) private var preferences

    /// Weather ambience lives on EVERY expanded page — the compact bar
    /// stays untouched.
    private var ambienceActive: Bool {
        viewModel.isExpanded
            && preferences.settings.weatherEnabled
    }

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

                // Light mode: keep a black cap hugging the physical camera
                // housing — a light surface around black hardware reads broken.
                if viewModel.isExpanded, viewModel.geometry.hasNotch {
                    NotchShape(bottomRadius: 10)
                        .fill(Color.black)
                        .frame(
                            width: viewModel.geometry.notchWidth + 28,
                            height: viewModel.geometry.topInset
                        )
                }

                // Sky BEHIND the content but ABOVE the black cap: the night
                // veil, stars and moon mix into the cap instead of leaving
                // it a dead black bar.
                if ambienceActive {
                    WeatherSkyView(phase: weather.phase)
                        .clipShape(panelShape)
                        .transition(.opacity)
                }

                content

                // Precipitation ABOVE everything — rain falls ON the cards
                // and mascots, like the iOS lock screen. Hit-testing is off,
                // so the layer is pure visual.
                if ambienceActive {
                    WeatherForegroundOverlay(phase: weather.phase)
                        .clipShape(panelShape)
                        .transition(.opacity)
                }
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
