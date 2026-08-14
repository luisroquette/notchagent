# Graph Report - NotchAgent  (2026-08-14)

## Corpus Check
- 245 files · ~213,762 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3351 nodes · 7417 edges · 219 communities (158 shown, 61 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 591 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `94df93ca`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Expanded Usage Dashboard
- Provider Usage Cards
- Usage State Management
- AgentMeterCore UI Integration
- Pixel Overlay Components
- Value Formatters
- Dashboard Analytics
- Desk Protocol Models
- API Account Probes
- Windows Claude Quota
- Provider Status Components
- Provider Event Models
- Windows Codex Rollout Parser
- Windows Usage State Store
- Status Attention Aggregation
- Sparkle Update Controller
- Desk Provider State
- Precision Calibration Tests
- Budget Decision Advice
- macOS App Delegate
- Time and Alert Models
- Notch Shape Geometry
- Spending Dashboard UI
- Codex Onboarding States
- Provider Parser Tests
- Notch Panel Hit Testing
- BRL Exchange Rates
- Anthropic Usage Reader
- Application File Paths
- Desk Alert Tracker
- Overlay Labels and Theme
- Claude Session Blocks
- Windows Avalonia Entry Point
- Codex Window Parsing
- Desk Serial Transport
- Usage Gauge Metrics
- Windows Threshold Alerts
- Notch Alert Moments
- Firmware Model State
- Subscription Import Parsing
- Site HTML Validation
- Google Cloud Credentials
- X Console Reading
- Firmware Update Errors
- Cloud Subscription Sync
- Subscription Persistence Queue
- Application Logging
- Threshold Alert Logic
- Menu Bar Application
- Firecrawl Subscription Reader
- X Developer Console
- API Account Finances
- ChatGPT Subscription Reader
- API Financial Summary
- Firmware Package Updater
- Windows Usage Providers
- Windows Segmented Meter
- Desk Frame Codec Errors
- Gemini Usage Provider
- Firmware Package Manifest
- Claude Quota Parsing Tests
- Desk Bridge Coordination
- Account Spend Windows
- Subscription Renewal Ledger
- Windows Application Models
- Desk Touch Input
- Subscription Payment History
- Sanitized Diagnostics Protocols
- API Service Catalog
- Core Regression Tests
- Windows Preferences Aggregation
- Google Subscription Reader
- OpenAI Console Reader
- OpenRouter Console Reader
- Account Settings Interface
- Windows Claude Provider
- Desk Reliability Assessment
- Firmware Package Validation
- Subscription Coding Keys
- Anthropic API Billing
- Refresh Scheduling History
- Desk Setup Readiness
- Desk Integration Tests
- Application Settings Migration
- Claude Quota Probe
- Settings Serialization Keys
- Google AI Studio Reader
- Codex Onboarding Inspector
- Windows Floating Bar
- API Usage Provenance
- Quota Reconciliation Logic
- API Provider Parsers
- Twitter API Console Reader
- Desk Firmware Recovery
- Windows Runner Game
- Credential Store Isolation
- Windows Presentation Formatting
- Application Environment Bootstrap
- Desk Frame Codec
- Claude Transcript Parser
- Preferences Ambient Intelligence
- Blocked Recovery Coherence
- Notch Navigation Windowing
- Compact Notch View
- Usage Rhythm Charts
- Anthropic Subscription Console
- Settings And Desk Setup
- Snapshot Persistence Store
- Cloud Subscription Sync
- Notch Window Geometry
- Account Card Reordering
- Spending Summary Engine
- Subscription Store Ledger
- API Account Provider
- Account Integrity Audit
- DeepSeek Console Reader
- Menu Bar Navigation
- Burn Rate Projection
- Windows Fullscreen Detection
- Windows Settings Interface
- Desk Serial Protocol
- Usage Data Models
- Windows Codex Provider
- Windows Usage Models
- macOS Codex Provider
- Window Routing
- System Integration Services
- Burn Chart Visualization
- Expense Subscription Ledger
- Notch Runner Game
- Threshold Alert Tests
- Parser Formatter Tests
- Notch Geometry Tests
- Claude Usage Provider
- Model Pricing
- Alert Lifecycle Tests
- API Portal Login Views
- Windows Logging
- Settings Sections
- Status Aggregator Tests
- Incremental JSONL Parsing
- Appearance Theme Application
- Desk Firmware Control Loop
- Desk Serial Bridge
- Desk Firmware UI
- Anthropic Billing Parsing
- Documentation Interactions
- X Billing Parsing
- Sanitized Desk Diagnostics
- USB Device Discovery
- Desk Firmware Runtime
- Shared Billing Exclusions
- Desk Contract Tests
- Desk Distribution Tests
- Windows Avalonia Project
- Desk Beta Onboarding
- Desk Beta Gate
- Firmware Toolchain Verification
- Public Release Audit
- macOS App Infrastructure
- Firmware Release Packaging
- Desk Unit Labeling
- Desk Soak Testing
- Desk Firmware Build
- Desk Firmware Check
- macOS App Packaging
- App Notarization
- Consent Evidence Capture
- Factory Visual Evidence
- Publication Evidence Capture
- Smoke Test Evidence
- Touch Evidence Capture
- Touch Telemetry Observer
- Firmware Standard Input
- Firmware Release Verification
- Pre-Push Validation
- Swift Package Definition
- GitHub Actions Pinning
- Version Consistency Check
- Desk Beta Packaging
- Local Beta Packaging
- Beta Release Status
- Commercial Lot Gate
- Consent Approval Gate
- Factory Quality Control
- Factory Report Gate
- Factory Visual Gate
- Test Matrix Entry
- Test Matrix Gate
- Pilot Daily Workflow
- Pilot Readiness Gate
- Pilot Initialization
- Desk Power Cycling
- Procurement Approval Gate
- Desk Reconnection
- Reconnection Evidence Capture
- Desk Recovery Workflow
- Serial Port Resolution
- Soak Test Evidence
- Soak Test Status
- Telemetry Evidence Capture
- Telemetry Soak Test
- Desk Touch Testing
- Touch Test Summary
- Update Appcast Generation
- AI Visual Review Gate
- Desk Beta Release
- Provider Parser Tests
- Provider Console Readers
- Quota Estimation Memory
- Calm Retro UI Memory
- Desk Release Validation
- Subscription Store Architecture
- Xcode Project Targets
- API Financial Monitoring
- Product Documentation
- Product Interface Screens
- Product Interface Screenshots

## God Nodes (most connected - your core abstractions)
1. `AccountQuota` - 109 edges
2. `APIAccountProviderTests` - 84 edges
3. `NotchExpandedView` - 75 edges
4. `APIAccountUsage` - 70 edges
5. `ProviderID` - 64 edges
6. `AISubscription` - 62 edges
7. `APIServiceID` - 59 edges
8. `APIAccount` - 56 edges
9. `SubscriptionStore` - 56 edges
10. `UsageStore` - 55 edges

## Surprising Connections (you probably didn't know these)
- `NotchAgentDeskConnectionState` --references--> `.telemetrySamples`  [INFERRED]
  Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift → Tests/NotchAgentTests/NotchAgentDeskTests.swift
- `AppSettings` --calls--> `StatusAggregatorTests`  [INFERRED]
  Sources/NotchAgent/Core/Models/AppSettings.swift → Tests/NotchAgentTests/AggregatorAndFormatTests.swift
- `DeskDeviceTelemetry` --references--> `DeskConnectionStateRecorder`  [EXTRACTED]
  Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift → Tests/NotchAgentTests/NotchAgentDeskTests.swift
- `NotchAgentDeskConnectionState` --references--> `DeskConnectionStateRecorder`  [EXTRACTED]
  Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift → Tests/NotchAgentTests/NotchAgentDeskTests.swift
- `DeskTimestampedTelemetrySample` --references--> `Date`  [EXTRACTED]
  Tests/NotchAgentTests/NotchAgentDeskTests.swift → Sources/NotchAgent/Core/Utilities/Formatters.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **SubscriptionStore Three-Module Split** — graphify_out_memory_query_20260728_202551_trace_subscriptionstore_coupling_and_propose_a_spl_thin_subscriptionstore_facade, graphify_out_memory_query_20260728_202551_trace_subscriptionstore_coupling_and_propose_a_spl_subscriptionledger, graphify_out_memory_query_20260728_202551_trace_subscriptionstore_coupling_and_propose_a_spl_spendingengine, graphify_out_memory_query_20260728_202551_trace_subscriptionstore_coupling_and_propose_a_spl_subscriptionrepository [EXTRACTED 1.00]
- **5h Session Limit Tracking** — docs_img_alert_almost_empty_alert_card, docs_img_desktop_burn_burn_projection_chart, docs_img_dashboard_1_claude_code_provider_card [INFERRED 0.75]
- **NotchAgent Popover Carousel Panels** — docs_img_desktop_now_expanded_status_panel, docs_img_panel_burn_burn_rate_projection, docs_img_panel_models_claude_models_panel [INFERRED 0.75]
- **NotchAgent Quota Visualizations** — docs_img_notch_compact_dot_quota_indicator, docs_img_desktop_now_segmented_quota_meter, docs_img_panel_burn_usage_projection_chart [INFERRED 0.75]
- **Swipeable Panel Set (NOW, RHYTHM)** — docs_img_panel_now_now_panel, docs_img_panel_rhythm_rhythm_panel, docs_img_panel_now_page_dots [INFERRED 0.75]
- **Multi-Provider Quota Monitoring** — docs_img_dashboard_1_claude_code_provider_card, docs_img_dashboard_2_gemini_cli_provider_card [INFERRED 0.85]
- **Claude/Codex/Gemini provider trio — shared quota-provider abstraction compared for confidence** — sources_agentmetercore_claudeprovider, sources_agentmetercore_codexprovider, sources_agentmetercore_geminiprovider [INFERRED 0.85]
- **Retro 8-bit vocabulary reused across macOS notch and iOS/mobile design** — sources_agentmetercore_pixelglyph, sources_agentmetercore_segmentedmeter, sources_agentmetercore_theme, sources_notchagent_notchrunnerview [INFERRED 0.85]
- **Desk Beta 1 Release Assurance** — docs_notchagent_desk_beta_1_reliability_gates, docs_notchagent_desk_bom_procurement_gate, docs_notchagent_desk_factory_per_unit_qc, docs_notchagent_desk_pilot_acceptance_gates, docs_notchagent_desk_bom_notarized_distribution [INFERRED 0.95]
- **Desk Local-First Privacy Model** — readme_local_first_privacy, docs_notchagent_desk_desk_privacy_boundary, docs_notchagent_desk_onboarding_explicit_mirroring_consent, firmware_notchagent_desk_readme_nonce_authenticated_ram_snapshot, docs_api_account_monitoring_safe_diagnostics [INFERRED 0.95]

## Communities (219 total, 61 thin omitted)

### Community 0 - "Expanded Usage Dashboard"
Cohesion: 0.09
Nodes (23): NotchExpandedView, .apiAccountsPage, .apiDashboardHeadline, .apiIsRefreshing, .apiRefreshCaption, .apiSpendWindowCaption, .apiUsage, .body (+15 more)

### Community 1 - "Provider Usage Cards"
Cohesion: 0.16
Nodes (14): ProviderCardView, .body, .quotaChip, .refreshText, .unavailable, AttentionLevel, Color, GaugeMetric (+6 more)

### Community 10 - "Usage State Management"
Cohesion: 0.08
Nodes (29): UsageStore, AppSettings, AttentionLevel, Bool, Double, Int, Never, PercentSample (+21 more)

### Community 100 - "AgentMeterCore UI Integration"
Cohesion: 0.18
Nodes (4): DecisionAdvisor, AgentMeterCore, Charts, UniformTypeIdentifiers

### Community 102 - "Pixel Overlay Components"
Cohesion: 0.10
Nodes (17): PixelGlyph, SegmentedMeter, .body, .runnerGame, .body, Color, Double, Int (+9 more)

### Community 103 - "Value Formatters"
Cohesion: 0.27
Nodes (5): Format, Timestamps, Double, Int, String

### Community 104 - "Dashboard Analytics"
Cohesion: 0.16
Nodes (15): DashboardView, .body, .controls, .decisionMode, .eventLog, .filteredEvents, .filteredPoints, .historyChart (+7 more)

### Community 105 - "Desk Protocol Models"
Cohesion: 0.09
Nodes (37): BurnPoint, DeskDeviceTelemetry, DeskHello, DeskHelloAcknowledgement, DeskSnapshot, DeskSnapshotFactory, Model, NotchAgentDeskConnectionState (+29 more)

### Community 106 - "API Account Probes"
Cohesion: 0.32
Nodes (4): APIAccountProbe, String, URL, URLSession

### Community 107 - "Windows Claude Quota"
Cohesion: 0.17
Nodes (11): ClaudeQuota, ClaudeQuotaProbe, ClaudeQuotaStatus, ClaudeTokenLocator, HttpClient, IReadOnlyDictionary, bool, CancellationToken (+3 more)

### Community 109 - "Provider Status Components"
Cohesion: 0.12
Nodes (19): ProviderHealth, AttentionDot, SparklineView, UsageBar, degraded, .isUsable, noData, notInstalled (+11 more)

### Community 11 - "Provider Event Models"
Cohesion: 0.08
Nodes (33): AttentionLevel, Kind, ProviderAlert, RefreshState, UsageEvent, ProviderID, ProviderInstallation, Comparable (+25 more)

### Community 110 - "Windows Codex Rollout Parser"
Cohesion: 0.16
Nodes (9): CodexRateWindow, CodexRolloutParser, CodexTokenInfo, JsonlReader, ReadOnlyMemory, DateTimeOffset, JsonElement, Action (+1 more)

### Community 112 - "Windows Usage State Store"
Cohesion: 0.09
Nodes (24): EventKind, ProviderAlert, RestoreMoment, ThresholdAlert, UsageEvent, ProviderHealth, ProviderHealthExtensions, ProviderId (+16 more)

### Community 115 - "Status Attention Aggregation"
Cohesion: 0.40
Nodes (5): StatusAggregator, AppSettings, AttentionLevel, ProviderAlert, UsageSnapshot

### Community 116 - "Sparkle Update Controller"
Cohesion: 0.25
Nodes (6): AppUpdateController, .isConfigured, Bool, Bundle, Sparkle, SPUStandardUpdaterController

### Community 117 - "Desk Provider State"
Cohesion: 0.20
Nodes (10): ProviderState, attention, burn, exhaustEpochMs, id, refresh, remaining, resetEpochMs (+2 more)

### Community 118 - "Precision Calibration Tests"
Cohesion: 0.31
Nodes (4): PrecisionCalibrationTests, Int, String, URL

### Community 12 - "Budget Decision Advice"
Cohesion: 0.09
Nodes (24): MonthlyBudgetAlert, MonthlyBudgetLevel, MonthlyBudgetStatus, MonthlySpendSummary, DecisionAdvice, Severity, Int, critical (+16 more)

### Community 120 - "macOS App Delegate"
Cohesion: 0.22
Nodes (6): AppDelegate, Notification, NSApplication, NSApplicationDelegate, NSObject, Bool

### Community 121 - "Time and Alert Models"
Cohesion: 0.11
Nodes (21): AgentMeterProduct, MetricProvenance, MetricSource, PercentSample, Projection, RestoreMoment, Date, DeskSoakRecord (+13 more)

### Community 122 - "Notch Shape Geometry"
Cohesion: 0.29
Nodes (6): NotchShape, AnimatablePair, Shape, .animatableData, CGFloat, CGRect

### Community 123 - "Spending Dashboard UI"
Cohesion: 0.13
Nodes (19): AIExpense.Kind, AIExpense.Source, BRLFormat, ExpenseEditor, PlanEditor, SpendingView, Double, .spendingSummary (+11 more)

### Community 124 - "Codex Onboarding States"
Cohesion: 0.15
Nodes (11): CodexOnboardingAction, CodexOnboardingStatus, authenticate, createFirstSession, openInstallGuide, .action, noSession, notAuthenticated (+3 more)

### Community 125 - "Provider Parser Tests"
Cohesion: 0.15
Nodes (6): CodexParserTests, GeminiParserTests, URL, .fixtureURL, .fixtureURL, URL

### Community 127 - "Notch Panel Hit Testing"
Cohesion: 0.20
Nodes (8): NotchHitTestView, NSHostingView, NSPoint, NSView, .interactiveRect, CGRect, AnyView, CGRect

### Community 129 - "BRL Exchange Rates"
Cohesion: 0.24
Nodes (6): BRLExchangeRateService, Calendar, Data, Decimal, URL, URLSession

### Community 13 - "Anthropic Usage Reader"
Cohesion: 0.17
Nodes (15): AnthropicUsageQuotaReader, Match, Range, CheckedContinuation, ClaudeQuota, Double, Error, Int (+7 more)

### Community 130 - "Application File Paths"
Cohesion: 0.29
Nodes (6): AppPaths, FileStamp, .appSupport, .home, Int, URL

### Community 131 - "Desk Alert Tracker"
Cohesion: 0.25
Nodes (8): AlertTracker, firedMask, id, initialized, lowestRemaining, observed, resetEpochMs, window

### Community 132 - "Overlay Labels and Theme"
Cohesion: 0.08
Nodes (35): ThemeMode, GaugeLabel, StatusPill, Theme, APIServiceLogo, ColorScheme, Font, ModelUsage (+27 more)

### Community 134 - "Windows Avalonia Entry Point"
Cohesion: 0.33
Nodes (4): Program, AppBuilder, NotchAgent.Windows, STAThread

### Community 135 - "Codex Window Parsing"
Cohesion: 0.10
Nodes (28): Incident, Payload, StatusPageService, CodexRateWindow, CodexRolloutParser, CodexTokenInfo, Event, Info (+20 more)

### Community 14 - "Desk Serial Transport"
Cohesion: 0.20
Nodes (9): NotchAgentDeskSerialTransport, Data, Int32, Never, Sendable, T, UInt32, UInt8 (+1 more)

### Community 140 - "Usage Gauge Metrics"
Cohesion: 0.40
Nodes (4): GaugeMetric, .remaining, Bool, UsageSnapshot

### Community 143 - "Windows Threshold Alerts"
Cohesion: 0.18
Nodes (6): ThresholdAlerts, AttentionLevel, double, HashSet, int, ThresholdAlert

### Community 147 - "Notch Alert Moments"
Cohesion: 0.11
Nodes (16): AlertMomentView, RestoreMomentView, NotchContainerView, .headline, .message, .pulseSpeed, .severityColor, Color (+8 more)

### Community 149 - "Firmware Model State"
Cohesion: 0.40
Nodes (5): ModelState, latency, name, status, tokens

### Community 15 - "Subscription Import Parsing"
Cohesion: 0.07
Nodes (29): CloudSyncFailure, InvoiceImportParser, InvoiceImportPreview, ParseFailure, RawSubscription, SubscriptionImportFormat, SubscriptionImportIssue, SubscriptionImportParser (+21 more)

### Community 156 - "X Console Reading"
Cohesion: 0.50
Nodes (4): Phase, dashboard, locatingAccount, usage

### Community 157 - "Firmware Update Errors"
Cohesion: 0.18
Nodes (11): DeskFirmwareUpdateError, LocalizedError, .errorDescription, flashFailed, flashTimedOut, integrityFailure, invalidApplicationSignature, invalidDevice (+3 more)

### Community 159 - "Cloud Subscription Sync"
Cohesion: 0.22
Nodes (8): CloudSyncState, CloudKit, failed, localOnly, synced, syncing, unavailable, waitingToRetry

### Community 16 - "Subscription Persistence Queue"
Cohesion: 0.11
Nodes (15): SpendDisplayCurrency, SubscriptionRepository, SubscriptionStorePreferences, brl, .code, usd, Bool, Decimal (+7 more)

### Community 17 - "Threshold Alert Logic"
Cohesion: 0.22
Nodes (9): ThresholdAlert, ThresholdAlerts, AttentionLevel, Bool, Double, Int, Set, String (+1 more)

### Community 172 - "Menu Bar Application"
Cohesion: 0.20
Nodes (8): NotchAgentApp, MenuBarLabelView, Scene, .body, .body, .summaryText, .symbolName, String

### Community 18 - "Firecrawl Subscription Reader"
Cohesion: 0.11
Nodes (18): Currency, FirecrawlSubscriptionReader, RecurringAmount, brl, usd, Bool, Character, CheckedContinuation (+10 more)

### Community 19 - "X Developer Console"
Cohesion: 0.17
Nodes (15): XConsoleValueStabilizer, XDeveloperConsoleReader, Bool, CheckedContinuation, Error, Int, MainActor, Never (+7 more)

### Community 2 - "API Account Finances"
Cohesion: 0.10
Nodes (21): APIAccount, APIAccountBilling, APIAccountDashboardRow, APIAccountDisplayConfidence, APIAccountFinancePresentation, APIAccountMoneyPresentation, APIAccountOrdering, Bool (+13 more)

### Community 20 - "ChatGPT Subscription Reader"
Cohesion: 0.11
Nodes (20): ChatGPTSubscriptionReader, Currency, RecurringAmount, brl, usd, .monthlyDecimal, Bool, Character (+12 more)

### Community 204 - "API Financial Summary"
Cohesion: 0.22
Nodes (6): APIAccountFinancialSummary, .availableUSD, .isComplete, Bool, Double, Int

### Community 207 - "Firmware Package Updater"
Cohesion: 0.32
Nodes (4): NotchAgentDeskFirmwareUpdater, Bundle, Int32, TimeInterval

### Community 208 - "Windows Usage Providers"
Cohesion: 0.29
Nodes (5): IUsageProvider, ProviderInstallation, ProviderInstallationKind, CancellationToken, Task

### Community 211 - "Windows Segmented Meter"
Cohesion: 0.29
Nodes (5): SegmentedMeter, Control, DrawingContext, IBrush, StyledProperty

### Community 212 - "Desk Frame Codec Errors"
Cohesion: 0.29
Nodes (7): DeskFrameCodecError, incompatibleProtocol, invalidChecksum, invalidCOBS, invalidHeader, invalidLength, payloadTooLarge

### Community 214 - "Gemini Usage Provider"
Cohesion: 0.19
Nodes (8): ProviderCapabilities, GeminiProvider, OptionSet, Int, AppSettings, ProviderInstallation, URL, UsageSnapshot

### Community 215 - "Firmware Package Manifest"
Cohesion: 0.40
Nodes (5): Manifest, sha256(), CryptoKit, String, UInt32

### Community 22 - "Desk Bridge Coordination"
Cohesion: 0.20
Nodes (7): NotchAgentDeskCoordinator, NotchAgentDeskSoakRecorder, Bool, Task, UsageStore, JSONEncoder, String

### Community 220 - "Account Spend Windows"
Cohesion: 0.40
Nodes (4): APIAccountSpendWindow, Calendar, DateInterval, TimeInterval

### Community 23 - "Subscription Renewal Ledger"
Cohesion: 0.10
Nodes (19): AISubscription, BillingCycle, SubscriptionSummary, SubscriptionSyncSnapshot, SubscriptionTests, .cycleTotalBRL, .monthlyEquivalentBRL, .projectedAnnualBRL (+11 more)

### Community 24 - "Windows Application Models"
Cohesion: 0.12
Nodes (14): SnapshotStore, PercentSample, CompactBarView, ProviderCardView, NotchAgent.Windows.UI, NotchAgent.Windows.Models, NotchAgent.Windows.Providers.Shared, NotchAgent.Windows.Providers (+6 more)

### Community 25 - "Desk Touch Input"
Cohesion: 0.09
Nodes (15): DeskTouch, synchronized(), ARDUINO_ISR_ATTR, instance_, interruptPending_, lastPollAtMs_, mux_, pendingAtMicros_ (+7 more)

### Community 26 - "Subscription Payment History"
Cohesion: 0.12
Nodes (17): FinancialHistory, MonthlyProviderSpend, Array, SubscriptionHistoryEvent, SubscriptionHistoryKind, .id, Calendar, Decimal (+9 more)

### Community 27 - "Sanitized Diagnostics Protocols"
Cohesion: 0.09
Nodes (29): APIAccountAuditOutcome, AccountRecord, DeskRecord, ProviderRecord, SanitizedDiagnosticExporter, SanitizedDiagnosticReport, FrameType, Sendable (+21 more)

### Community 28 - "API Service Catalog"
Cohesion: 0.05
Nodes (36): APIServiceID, .addableCases, anthropicAPI, anthropicConsole, artificialAnalysis, brAPI, chatGPTSubscription, .credentialPlaceholder (+28 more)

### Community 29 - "Core Regression Tests"
Cohesion: 0.11
Nodes (8): InvoiceImportTests, ProductIdentityTests, PricingTests, CostLayersTests, DecisionAdvisorTests, AppSettingsCompatibilityTests, ModelBreakdownTests, XCTestCase

### Community 30 - "Windows Preferences Aggregation"
Cohesion: 0.26
Nodes (6): AppSettings, ThemeMode, AttentionLevel, PreferencesStore, StatusAggregator, IEnumerable

### Community 31 - "Google Subscription Reader"
Cohesion: 0.13
Nodes (14): GoogleSubscriptionReader, Bool, Character, CheckedContinuation, Double, Error, Int, Never (+6 more)

### Community 32 - "OpenAI Console Reader"
Cohesion: 0.13
Nodes (15): OpenAIBalanceStabilizer, OpenAIConsoleReader, Bool, CheckedContinuation, Double, Error, Int, Never (+7 more)

### Community 33 - "OpenRouter Console Reader"
Cohesion: 0.13
Nodes (16): OpenRouterConsoleReader, OpenRouterSpendStabilizer, Bool, CheckedContinuation, Double, Error, Int, Never (+8 more)

### Community 34 - "Account Settings Interface"
Cohesion: 0.17
Nodes (15): APIAccountPortalConnectionSheet, APIAccountsSettingsSection, PortalLoginRequest, QuotaThresholdEditor, Binding, updated, .instructions, .body (+7 more)

### Community 35 - "Windows Claude Provider"
Cohesion: 0.07
Nodes (28): ClaudeProvider, ClaudeFileStat, ClaudeScanCache, ClaudeTranscriptParser, Entry, byte, Consumed, CostUsd (+20 more)

### Community 36 - "Desk Reliability Assessment"
Cohesion: 0.19
Nodes (8): DeskReliabilityAcceptance, DeskReliabilityAssessment, DeskTouchContinuityMonitor, Bool, Double, Self, String, UInt32

### Community 37 - "Firmware Package Validation"
Cohesion: 0.20
Nodes (10): DeskFirmwareManifest, DeskFirmwarePackage, ClosedRange, Bool, Int, Int64, Self, String (+2 more)

### Community 38 - "Subscription Coding Keys"
Cohesion: 0.12
Nodes (16): CodingKeys, CodingKey, basePriceBRL, billingCycle, history, id, isActive, nextRenewalDate (+8 more)

### Community 39 - "Anthropic API Billing"
Cohesion: 0.14
Nodes (13): AnthropicAPIConsoleReader, Calendar, CheckedContinuation, Double, Error, Int, Never, String (+5 more)

### Community 4 - "Refresh Scheduling History"
Cohesion: 0.09
Nodes (20): UsageProvider, RefreshGenerationTracker, RefreshRequestQueue, RefreshScheduler, HistoryStore, Point, RefreshSchedulerTests, Bool (+12 more)

### Community 40 - "Desk Setup Readiness"
Cohesion: 0.12
Nodes (13): NotchAgentDeskSetupStatus, StepState, .canEnableMirroring, .hasLocalProvider, .hasProviderError, .isReady, actionRequired, ready (+5 more)

### Community 41 - "Desk Integration Tests"
Cohesion: 0.23
Nodes (9): DeskFrameStreamDecoder, DeskConnectionStateRecorder, NotchAgentDeskTests, ContinuousClock, .last, .telemetrySamples, Data, Duration (+1 more)

### Community 42 - "Application Settings Migration"
Cohesion: 0.09
Nodes (15): AppSettings, InterfaceLanguage, ProviderIntegrationTests, apiAccountIdentifiers, apiAccounts, en, .label, ptBR (+7 more)

### Community 43 - "Claude Quota Probe"
Cohesion: 0.11
Nodes (17): ClaudeQuota, ClaudeQuotaProbe, ClaudeTokenLocator, Entry, FileScanCache, Data, Double, Int (+9 more)

### Community 44 - "Settings Serialization Keys"
Cohesion: 0.09
Nodes (22): CodingKeys, apiAccountMonitoringEnabled, claudeQuotaProbeConsentVersion, claudeQuotaProbeEnabled, claudeSessionTokenBudget, claudeWeeklyTokenBudget, criticalThresholdPercent, fallbackPillEnabled (+14 more)

### Community 45 - "Google AI Studio Reader"
Cohesion: 0.19
Nodes (13): GoogleAIStudioConsoleReader, CheckedContinuation, Double, Error, Int, Never, String, Task (+5 more)

### Community 46 - "Codex Onboarding Inspector"
Cohesion: 0.17
Nodes (10): CodexOnboardingInspector, CodexProcessInvocation, FileManager, .sessionsURL, Bool, Duration, Int, Int32 (+2 more)

### Community 47 - "Windows Floating Bar"
Cohesion: 0.07
Nodes (19): App, RefreshScheduler, FloatingBarWindow, TrayIconFactory, Application, IClassicDesktopStyleApplicationLifetime, NativeMenuItem, PointerPressedEventArgs (+11 more)

### Community 48 - "API Usage Provenance"
Cohesion: 0.08
Nodes (32): APIAccountDataOrigin, APIAccountFieldOrigins, APIAccountMoneyKind, APIAccountReadStatus, APIAccountSpendPeriod, APIAccountUsage, APIAccountAuditItem, Hashable (+24 more)

### Community 49 - "Quota Reconciliation Logic"
Cohesion: 0.16
Nodes (5): AccountQuota, APIAccountOfficialComparator, Decimal, Double, Int

### Community 5 - "API Provider Parsers"
Cohesion: 0.07
Nodes (5): APIAccountProviderTests, .total, Any, Data, DateInterval

### Community 51 - "Twitter API Console Reader"
Cohesion: 0.14
Nodes (14): TwitterAPIIOConsoleReader, Any, CheckedContinuation, Data, Double, Error, Int, Never (+6 more)

### Community 52 - "Desk Firmware Recovery"
Cohesion: 0.14
Nodes (12): DeskFirmwareRecoveryEligibility, DeskFirmwareVerification, NotchAgentDeskUpdateState, Security, installed, versionMismatch, waiting, failed (+4 more)

### Community 53 - "Windows Runner Game"
Cohesion: 0.19
Nodes (11): RunnerControl, DateTime, Size, Typeface, Color, DateTimeOffset, DispatcherTimer, double (+3 more)

### Community 55 - "Windows Presentation Formatting"
Cohesion: 0.10
Nodes (17): Format, Failure, Idle, Refreshing, RefreshState, Success, AppTheme, BarViewModel (+9 more)

### Community 56 - "Application Environment Bootstrap"
Cohesion: 0.15
Nodes (14): AppEnvironment, NotificationService, Bool, Never, PreferencesStore, RefreshScheduler, SnapshotStore, Task (+6 more)

### Community 57 - "Desk Frame Codec"
Cohesion: 0.23
Nodes (9): CRC32, DeskFrame, DeskFrameCodec, NotchAgentDeskProtocol, Data, Int, Result, UInt32 (+1 more)

### Community 58 - "Claude Transcript Parser"
Cohesion: 0.13
Nodes (22): ClaudeFileStat, ClaudeScanCache, ClaudeTranscriptParser, Entry, HourStat, Line, Message, ModelStat (+14 more)

### Community 59 - "Preferences Ambient Intelligence"
Cohesion: 0.11
Nodes (15): PreferencesStore, DeskAmbientRecommendation, NotchAgentDeskAmbientIntelligence, Page, .settings, AppSettings, UserDefaults, burn (+7 more)

### Community 6 - "Blocked Recovery Coherence"
Cohesion: 0.22
Nodes (6): BlockedCoherenceTests, RestoreMomentTests, Bool, Double, UsageSnapshot, UsageStore

### Community 60 - "Notch Navigation Windowing"
Cohesion: 0.10
Nodes (20): Mode, NotchViewModel, ScrollPagingTests, Edge, NSEvent, compact, expanded, .compactSize (+12 more)

### Community 61 - "Compact Notch View"
Cohesion: 0.31
Nodes (8): NotchCompactView, .body, Bool, Color, GaugeMetric, String, UsageSnapshot, View

### Community 62 - "Usage Rhythm Charts"
Cohesion: 0.25
Nodes (8): PagerDots, RhythmChartView, .body, .body, CGSize, Color, Double, Int

### Community 63 - "Anthropic Subscription Console"
Cohesion: 0.21
Nodes (10): AnthropicConsoleReader, CheckedContinuation, Error, Int, Never, Task, UUID, Void (+2 more)

### Community 64 - "Settings And Desk Setup"
Cohesion: 0.23
Nodes (3): SettingsView, .body, Decimal

### Community 65 - "Snapshot Persistence Store"
Cohesion: 0.28
Nodes (5): SnapshotStore, JSONDecoder, JSONEncoder, URL, UsageSnapshot

### Community 66 - "Cloud Subscription Sync"
Cohesion: 0.33
Nodes (5): CloudSubscriptionSync, CKContainer, CKDatabase, CKRecord, String

### Community 67 - "Notch Window Geometry"
Cohesion: 0.15
Nodes (10): NotchPanel, NotchWindowController, NSPanel, NSRect, NSScreen, .canBecomeKey, .canBecomeMain, Bool (+2 more)

### Community 68 - "Account Card Reordering"
Cohesion: 0.25
Nodes (5): APIAccountCardDropDelegate, DropDelegate, DropInfo, DropProposal, UUID

### Community 69 - "Spending Summary Engine"
Cohesion: 0.30
Nodes (6): SpendingEngine, Bool, Decimal, Double, String, .monthlyBudgetStatus

### Community 7 - "Subscription Store Ledger"
Cohesion: 0.10
Nodes (13): SubscriptionRepositoryProtocol, SubscriptionStore, AnyObject, Combine, ObservableObject, .monthlySpend, .summary, Bool (+5 more)

### Community 70 - "API Account Provider"
Cohesion: 0.17
Nodes (7): APIAccountProvider, APIAccountSnapshotCache, AppSettings, ProviderInstallation, TimeInterval, UInt64, UsageSnapshot

### Community 71 - "Account Integrity Audit"
Cohesion: 0.36
Nodes (5): APIAccountAuditTolerance, APIAccountIntegrityAuditor, Decimal, Double, TimeInterval

### Community 72 - "DeepSeek Console Reader"
Cohesion: 0.15
Nodes (12): DeepSeekConsoleReader, CheckedContinuation, Double, Error, Int, Never, String, Task (+4 more)

### Community 74 - "Menu Bar Navigation"
Cohesion: 0.12
Nodes (16): MenuBarContentView, Tab, Bindable, .costs, .header, .overview, .tabPicker, PreferencesStore (+8 more)

### Community 75 - "Burn Rate Projection"
Cohesion: 0.21
Nodes (6): BurnRate, BurnRateTests, String, TimeInterval, Double, PercentSample

### Community 76 - "Windows Fullscreen Detection"
Cohesion: 0.25
Nodes (9): FullscreenDetector, MonitorInfo, Rect, DllImport, IntPtr, MonitorInfo, Rect, uint (+1 more)

### Community 78 - "Windows Settings Interface"
Cohesion: 0.20
Nodes (8): SettingsWindow, NumericUpDownValueChangedEventArgs, RangeBaseValueChangedEventArgs, SelectionChangedEventArgs, Window, Action, bool, RoutedEventArgs

### Community 79 - "Desk Serial Protocol"
Cohesion: 0.22
Nodes (13): FrameView, append32(), cobsDecode(), cobsEncode(), crc32(), decodeFrame(), read32(), writeFrame() (+5 more)

### Community 8 - "Usage Data Models"
Cohesion: 0.10
Nodes (33): CostEstimate, DailyTotal, HourlyTotal, ModelHealth, ModelProbeStatus, ModelUsage, QuotaStatus, SessionUsage (+25 more)

### Community 81 - "Windows Codex Provider"
Cohesion: 0.11
Nodes (15): CodexProvider, AppPaths, FileScan, FileStamp, IUsageProvider, Regex, CancellationToken, DateTimeOffset (+7 more)

### Community 82 - "Windows Usage Models"
Cohesion: 0.14
Nodes (18): CostEstimate, DailyTotal, GaugeMetric, HourlyTotal, ModelUsage, SessionUsage, TokenUsage, WeeklyUsage (+10 more)

### Community 83 - "macOS Codex Provider"
Cohesion: 0.12
Nodes (8): CodexProvider, CurrentWindowParityTests, StaleWindowTests, ProviderInstallation, TimeInterval, URL, URL, URL

### Community 84 - "Window Routing"
Cohesion: 0.41
Nodes (7): WindowRouter, NSSize, NSWindow, AnyView, String, .body, .footer

### Community 85 - "System Integration Services"
Cohesion: 0.24
Nodes (8): BundleContext, LoginItem, ServiceManagement, .isBundledApp, .isAvailable, .isEnabled, Bool, UserNotifications

### Community 86 - "Burn Chart Visualization"
Cohesion: 0.22
Nodes (12): BurnChartView, .body, .polyline, .span, .visibleSamples, Bool, CGFloat, CGSize (+4 more)

### Community 87 - "Expense Subscription Ledger"
Cohesion: 0.08
Nodes (28): AIExpense, Kind, Source, AgentMeterProvider, SubscriptionLedger, CostReconciliation, EstimatedCostLayers, ProviderReconciliation (+20 more)

### Community 88 - "Notch Runner Game"
Cohesion: 0.26
Nodes (13): NotchRunnerView, Path, .body, .difficulty, .obstacleOffsets, .spacingScale, .speed, Bool (+5 more)

### Community 90 - "Parser Formatter Tests"
Cohesion: 0.17
Nodes (4): FormatTests, ClaudeParserTests, .fixtureURL, URL

### Community 91 - "Notch Geometry Tests"
Cohesion: 0.16
Nodes (8): PreviewData, NotchGeometry, GeometryTests, Bool, Bool, CGFloat, CGRect, CGSize

### Community 92 - "Claude Usage Provider"
Cohesion: 0.13
Nodes (12): ClaudeProvider, ClaudeFileStat, .paidProbeAllowed, Bool, ClaudeQuota, ClaudeQuotaProbe, Double, ProviderInstallation (+4 more)

### Community 93 - "Model Pricing"
Cohesion: 0.42
Nodes (5): ModelPricing, PricingTable, Double, String, TokenUsage

### Community 94 - "Alert Lifecycle Tests"
Cohesion: 0.33
Nodes (4): ThresholdLifecycleTests, Double, UsageSnapshot, UsageStore

### Community 95 - "API Portal Login Views"
Cohesion: 0.20
Nodes (8): APIAccountPortalLoginView, APIAccountPortalSession, Context, NSViewRepresentable, UUID, WKWebView, .body, WKWebViewConfiguration

### Community 96 - "Windows Logging"
Cohesion: 0.39
Nodes (3): Log, Logger, string

### Community 97 - "Settings Sections"
Cohesion: 0.50
Nodes (4): SettingsSection, desk, general, .id

### Community 98 - "Status Aggregator Tests"
Cohesion: 0.29
Nodes (4): StatusAggregatorTests, Double, ProviderHealth, UsageSnapshot

### Community 99 - "Incremental JSONL Parsing"
Cohesion: 0.11
Nodes (13): JSONLReader, IncrementalParseTests, FileHandle, Bool, Data, Int, UInt64, URL (+5 more)

### Community 111 - "Desk Firmware Control Loop"
Cohesion: 0.16
Nodes (15): alertTouchEvent(), clearData(), dismissDeskAlert(), evaluateDeskAlerts(), handleFrame(), loop(), navEvent(), navigatePage() (+7 more)

### Community 113 - "Desk Serial Bridge"
Cohesion: 0.27
Nodes (8): deskPaths(), registryInteger(), Darwin, IOKit, IOKit.serial, Int, io_service_t, String

### Community 114 - "Desk Firmware UI"
Cohesion: 0.52
Nodes (7): createAlertOverlay(), createGame(), createUI(), label(), setup(), styleTracking(), surface()

### Community 137 - "Documentation Interactions"
Cohesion: 0.22
Nodes (6): header, recorder, recorderStates, recorderTabs, reveals, year

### Community 205 - "USB Device Discovery"
Cohesion: 0.32
Nodes (3): Int, io_service_t, String

### Community 209 - "Desk Firmware Runtime"
Cohesion: 0.16
Nodes (18): alertColor(), alertHeadline(), alertMessage(), attentionColor(), attentionText(), compactTokens(), estimatedEpochMs(), findProvider() (+10 more)

### Community 3 - "Shared Billing Exclusions"
Cohesion: 0.24
Nodes (5): Set, .apiAccountsExcludedFromTotal, Double, String, UUID

### Community 101 - "Desk Contract Tests"
Cohesion: 0.33
Nodes (9): assert_beta_status_invalid(), assert_bom_rejected(), assert_factory_rejected(), assert_matrix_rejected(), assert_pilot_rejected(), make_factory_telemetry(), make_factory_visual(), make_sample_report() (+1 more)

### Community 126 - "Windows Avalonia Project"
Cohesion: 0.25
Nodes (7): Avalonia (11.2.5), Avalonia.Desktop (11.2.5), Avalonia.Diagnostics (11.2.5), Avalonia.Fonts.Inter (11.2.5), Avalonia.Themes.Fluent (11.2.5), net8.0, Microsoft.NET.Sdk

### Community 144 - "Firmware Toolchain Verification"
Cohesion: 0.50
Nodes (3): ARDUINO_DIRECTORIES_USER, require_version(), verify-toolchain.sh script

### Community 146 - "Public Release Audit"
Cohesion: 0.70
Nodes (4): scan_current(), scan_history(), scan_new_personal_history(), audit-public-release.sh script

### Community 155 - "Desk Soak Testing"
Cohesion: 0.83
Nodes (3): cleanup(), fail_soak(), notchagent-desk-soak.sh script

### Community 221 - "Desk Beta Release"
Cohesion: 0.40
Nodes (4): Beta scope, Highlights, Installation, NotchAgent 3.1.1 — Desk Beta 1

### Community 77 - "Provider Console Readers"
Cohesion: 0.23
Nodes (3): Foundation, SwiftUI, WebKit

### Community 80 - "Quota Estimation Memory"
Cohesion: 0.23
Nodes (14): Memory query — 'relembre o projeto NotchAgent' (product overview), Memory query — quota estimation mechanism (Claude probe, Codex rollout, Gemini unavailable, burn rate), Memory query — confidence comparison, Mac quota estimate vs standalone iOS estimator, BurnRate — linear projection from recent percent samples, ClaudeProvider (code symbol referenced in memory queries), ClaudeQuotaProbe — one-token probe reading Anthropic 5h/7d headers, CodexProvider (code symbol referenced in memory queries), CodexRolloutParser — parses rollout JSONL used_percent/reset timestamps (+6 more)

### Community 145 - "Calm Retro UI Memory"
Cohesion: 0.40
Nodes (5): Memory query — reusing 8-bit retro vocabulary for iOS, excluding GAME OVER/runner for calm factual data, PixelGlyph — procedural pixel companion sprite, SegmentedMeter — truthful segmented-meter component, Theme (code symbol referenced in memory queries), NotchRunnerView (excluded retro runner animation, code symbol)

### Community 136 - "Desk Release Validation"
Cohesion: 0.33
Nodes (7): NotchAgent Desk Validation Pipeline, Public Release Security Audit, One-Way Public Repository Sync, Desk Beta 1 Reliability Gates, Firmware 0.6.16 Beta Candidate, Paid Probe Disable Guard, Fail-Closed Public Release Gate

### Community 141 - "Subscription Store Architecture"
Cohesion: 0.33
Nodes (6): SubscriptionStore UI Consumers, SubscriptionStore Financial State Hub, SpendingEngine, SubscriptionLedger, SubscriptionRepository, Thin SubscriptionStore Facade

### Community 154 - "Xcode Project Targets"
Cohesion: 0.67
Nodes (4): AgentMeterCore Target, NotchAgent macOS Target, NotchAgentTests Target, NotchAgent XcodeGen Specification

### Community 160 - "API Financial Monitoring"
Cohesion: 0.67
Nodes (3): API Financial Monitoring, Independent API Account Financial Fields, Financial Source Integrity and Reconciliation

### Community 21 - "Product Documentation"
Cohesion: 0.06
Nodes (33): NotchAgent 3.1.0 Beta 1, Isolated Per-Account Portal Sessions, Notarized Desk Distribution Contract, Desk Commercial Lot Gate, Mac-to-Desk Local Data Flow, Canonical Desk Onboarding URL, Desk Recovery Without Terminal, Desk Pilot Acceptance Gates (+25 more)

### Community 73 - "Product Interface Screens"
Cohesion: 0.19
Nodes (16): Carousel Pagination Dots, Expanded Status Panel, Refresh Pause Dashboard Settings Controls, Segmented Quota Meter, Service Quota Card, Compact Notch Bar, Dot Quota Indicator, Burn Rate Projection Panel (+8 more)

### Community 9 - "Product Interface Screenshots"
Cohesion: 0.06
Nodes (46): Almost Empty Alert Card, Pixel Space-Invader Mascot, Segmented Quota Progress Bar, Claude Code Provider Card, Hourly Rhythm Bar Chart, Range and Provider Filter Toggle, Session Tokens Over Time Chart, Events Log Section (+38 more)

## Knowledge Gaps
- **506 isolated node(s):** `EventKind`, `AgentMeterProduct`, `Log`, `ProviderInstallationKind`, `PercentSample` (+501 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **61 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Date` connect `Time and Alert Models` to `Expanded Usage Dashboard`, `BRL Exchange Rates`, `API Account Finances`, `Application File Paths`, `Refresh Scheduling History`, `API Provider Parsers`, `Blocked Recovery Coherence`, `Codex Window Parsing`, `Usage Data Models`, `Subscription Store Ledger`, `Usage State Management`, `Provider Event Models`, `Budget Decision Advice`, `Anthropic Usage Reader`, `X Billing Parsing`, `Subscription Import Parsing`, `Subscription Persistence Queue`, `Threshold Alert Logic`, `Firecrawl Subscription Reader`, `Subscription Renewal Ledger`, `Subscription Payment History`, `Sanitized Diagnostics Protocols`, `Claude Session Blocks`, `Provider Usage Cards`, `Cloud Subscription Sync`, `OpenRouter Console Reader`, `Anthropic API Billing`, `Application Settings Migration`, `Claude Quota Probe`, `Google AI Studio Reader`, `Codex Onboarding Inspector`, `API Usage Provenance`, `Quota Reconciliation Logic`, `Twitter API Console Reader`, `Claude Transcript Parser`, `Preferences Ambient Intelligence`, `API Account Provider`, `DeepSeek Console Reader`, `Burn Rate Projection`, `macOS Codex Provider`, `Burn Chart Visualization`, `Expense Subscription Ledger`, `Notch Runner Game`, `Parser Formatter Tests`, `Account Spend Windows`, `Claude Usage Provider`, `Value Formatters`, `Desk Protocol Models`, `API Account Probes`, `Precision Calibration Tests`?**
  _High betweenness centrality (0.181) - this node is a cross-community bridge._
- **Why does `AccountQuota` connect `Quota Reconciliation Logic` to `Anthropic Billing Parsing`, `API Provider Parsers`, `X Billing Parsing`, `Firecrawl Subscription Reader`, `X Developer Console`, `ChatGPT Subscription Reader`, `Sanitized Diagnostics Protocols`, `API Service Catalog`, `Google Subscription Reader`, `OpenAI Console Reader`, `OpenRouter Console Reader`, `Anthropic API Billing`, `Google AI Studio Reader`, `API Usage Provenance`, `Twitter API Console Reader`, `Anthropic Subscription Console`, `API Account Provider`, `DeepSeek Console Reader`, `API Account Probes`, `Time and Alert Models`?**
  _High betweenness centrality (0.143) - this node is a cross-community bridge._
- **Why does `NotchAgentApp` connect `Menu Bar Application` to `Windows Floating Bar`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `AccountQuota` (e.g. with `APIAccountFieldOrigins` and `.testDeepSeekMergePrefersConsoleSpendAndAPIBalance()`) actually correct?**
  _`AccountQuota` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `EventKind`, `AgentMeterProduct`, `Log` to the rest of the system?**
  _506 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Expanded Usage Dashboard` be split into smaller, more focused modules?**
  _Cohesion score 0.09490196078431372 - nodes in this community are weakly interconnected._
- **Should `Usage State Management` be split into smaller, more focused modules?**
  _Cohesion score 0.0821256038647343 - nodes in this community are weakly interconnected._