import Foundation

/// Product-facing setup state. It intentionally exposes no paths, account IDs,
/// credentials, or hardware identifiers.
struct NotchAgentDeskSetupStatus: Equatable {
    enum StepState: Equatable {
        case ready
        case waiting
        case actionRequired
    }

    let desk: StepState
    let claude: StepState
    let codex: StepState
    let mirroring: StepState

    init(
        connectionPhase: NotchAgentDeskConnectionState.Phase,
        mirroringEnabled: Bool,
        claudeInstallation: ProviderInstallation,
        codexInstallation: ProviderInstallation,
        claudeHealth: ProviderHealth?,
        codexHealth: ProviderHealth?,
        claudeRefreshState: RefreshState,
        codexRefreshState: RefreshState
    ) {
        switch connectionPhase {
        case .connected:
            desk = .ready
        case .incompatible:
            desk = .actionRequired
        case .disabled, .searching, .handshaking:
            desk = .waiting
        }
        claude = Self.providerState(
            claudeInstallation,
            health: claudeHealth,
            refreshState: claudeRefreshState
        )
        codex = Self.providerState(
            codexInstallation,
            health: codexHealth,
            refreshState: codexRefreshState
        )
        mirroring = mirroringEnabled ? .ready : .actionRequired
    }

    var hasLocalProvider: Bool { claude == .ready || codex == .ready }

    var hasProviderError: Bool { claude == .actionRequired || codex == .actionRequired }

    var canEnableMirroring: Bool { desk == .ready && hasLocalProvider }

    var isReady: Bool {
        canEnableMirroring && mirroring == .ready
    }

    private static func providerState(
        _ installation: ProviderInstallation,
        health: ProviderHealth?,
        refreshState: RefreshState
    ) -> StepState {
        switch installation {
        case .installed:
            if case .failure = refreshState { return .actionRequired }
            guard case .success = refreshState else { return .waiting }
            switch health {
            case .ok, .degraded: return .ready
            case .parseError: return .actionRequired
            case .notInstalled, .noData, nil: return .waiting
            }
        case .notInstalled: return .waiting
        }
    }
}
