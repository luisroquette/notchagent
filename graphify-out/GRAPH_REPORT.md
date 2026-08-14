# Graph Report - notchagent-graphify-update.G0aEKu  (2026-08-14)

## Corpus Check
- 239 files · ~213,065 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 3326 nodes · 7388 edges · 193 communities (138 shown, 55 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 589 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `0b65dfbf`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- NotchExpandedView
- ProviderCardView
- APIAccountFieldOrigins
- .make
- RefreshScheduler
- APIAccountProviderTests
- .snapshot
- SubscriptionStore
- UsageSnapshot
- Settings Window
- UsageStore
- ProviderID
- MonthlyBudgetStatus
- AnthropicUsageQuotaReader
- NotchAgentDeskSerialTransport
- SubscriptionImportParser
- SubscriptionRepository
- .normalized
- FirecrawlSubscriptionReader
- XDeveloperConsoleReader
- ChatGPTSubscriptionReader
- NotchAgent
- NotchAgentDeskCoordinator
- AISubscription
- NotchAgent.Windows.Models
- DeskTouch
- Sendable
- .report
- APIServiceID
- XCTestCase
- ProviderId
- GoogleSubscriptionReader
- OpenAIConsoleReader
- OpenRouterConsoleReader
- String
- ClaudeProvider
- .assess
- DeskFirmwarePackage
- CodingKeys
- AnthropicAPIConsoleReader
- NotchAgentDeskTests
- .testSerialTransportWaitsForHandshakeThenPublishes
- AppSettings
- ModelHealth
- CodingKeys
- GoogleAIStudioConsoleReader
- SubscriptionLedger
- FloatingBarWindow
- APIAccount
- .findings
- XCTest
- TwitterAPIIOConsoleReader
- ThemeMode
- RunnerControl
- .value
- .Update
- AppEnvironment
- .encode
- .preview
- DeskAmbientRecommendation
- NotchViewModel
- View
- ProviderIntegrationTests
- AnthropicConsoleReader
- SnapshotStore
- CloudSyncState
- NotchWindowController
- APIAccountCardDropDelegate
- SpendingEngine
- APIAccountProvider
- APIAccountAuditItem
- DeepSeekConsoleReader
- Desktop NOW Panel Screenshot
- MenuBarContentView
- .project
- FullscreenDetector
- Foundation
- SettingsWindow
- desk_protocol.h
- CodexProvider
- UsageSnapshot
- CodexProvider
- WindowRouter
- SystemIntegration.swift
- BurnChartView
- .fromSnapshots
- ThresholdAlertsTests
- .parseISO8601
- NotchGeometry
- ClaudeProvider
- ModelPricing
- .snapshot
- .configuration
- Logger
- .snapshot
- IncrementalParseTests
- notchagent-desk-contract-tests.sh
- Format
- DashboardView
- Equatable
- AccountQuota
- ClaudeQuotaProbe
- .applyThemeMode
- ProviderHealth
- CodexRolloutParser.cs
- loop
- UsageStore
- NotchAgentDeskBridge.swift
- createUI
- .attention
- AppUpdateController
- ProviderState
- PrecisionCalibrationTests
- notchagent-desk-distribution-contract-tests.sh
- NSObject
- Date
- SpendingView
- CodexParserTests
- NotchAgent.Windows.csproj
- .latestUSDToBRL
- FileStamp
- AlertTracker
- GaugeLabel
- .currentBlock
- Program
- Decodable
- NotchAgent Desk Validation Pipeline
- script.js
- Configuração do NotchAgent Desk Beta 1
- notchagent-desk-beta1-gate.sh
- verify-toolchain.sh
- audit-public-release.sh
- AlertMomentView
- AppKit
- ModelState
- SiteParser
- package-release.sh
- notchagent-desk-unit-label.sh
- NotchAgent macOS Target
- notchagent-desk-soak.sh
- Independent API Account Financial Fields
- build.sh
- os
- check-notchagent-desk.sh
- make-app.sh
- notarize-app.sh
- notchagent-desk-consent-evidence.sh
- notchagent-desk-factory-visual-evidence.sh
- notchagent-desk-publication-evidence.sh
- notchagent-desk-smoke-evidence.sh
- notchagent-desk-touch-evidence.sh
- notchagent-desk-touch-observe.sh
- MenuBarLabelView
- consume-stdin.sh
- verify-release.sh
- pre-push
- Package.swift
- check-github-actions-pins.sh
- check-version.sh
- make-notchagent-desk-beta1.sh
- make-notchagent-desk-local-beta1.sh
- notchagent-desk-beta1-status.sh
- notchagent-desk-commercial-lot-gate.sh
- notchagent-desk-consent-gate.sh
- notchagent-desk-factory-qc.sh
- notchagent-desk-factory-report-gate.sh
- notchagent-desk-factory-visual-gate.sh
- notchagent-desk-matrix-entry.sh
- notchagent-desk-matrix-gate.sh
- notchagent-desk-pilot-day.sh
- notchagent-desk-pilot-gate.sh
- notchagent-desk-pilot-init.sh
- notchagent-desk-power-cycle.sh
- notchagent-desk-procurement-gate.sh
- notchagent-desk-reconnect.sh
- notchagent-desk-reconnect-evidence.sh
- notchagent-desk-recovery.sh
- notchagent-desk-resolve-port.sh
- notchagent-desk-soak-evidence.sh
- notchagent-desk-soak-status.sh
- notchagent-desk-telemetry-evidence.sh
- notchagent-desk-telemetry-soak.sh
- notchagent-desk-touch.sh
- notchagent-desk-touch-summary.sh
- .defaultCandidatePaths
- generate-update-appcast.sh
- notchagent_desk.ino
- SegmentedMeter
- DeskFrameCodecError
- notchagent-desk-ai-visual-review-gate.sh
- ClaudeQuotaProbeParseTests
- NotchAgent 3.1.1 — Desk Beta 1

## God Nodes (most connected - your core abstractions)
1. `AccountQuota` - 109 edges
2. `APIAccountProviderTests` - 84 edges
3. `NotchExpandedView` - 75 edges
4. `APIAccountUsage` - 70 edges
5. `ProviderID` - 64 edges
6. `AISubscription` - 62 edges
7. `APIServiceID` - 59 edges
8. `SubscriptionStore` - 56 edges
9. `APIAccount` - 56 edges
10. `UsageStore` - 55 edges

## Surprising Connections (you probably didn't know these)
- `.telemetrySamples` --references--> `NotchAgentDeskConnectionState`  [INFERRED]
  Tests/NotchAgentTests/NotchAgentDeskTests.swift → Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift
- `StatusAggregatorTests` --calls--> `AppSettings`  [INFERRED]
  Tests/NotchAgentTests/AggregatorAndFormatTests.swift → Sources/NotchAgent/Core/Models/AppSettings.swift
- `NotchAgentApp` --implements--> `App`  [EXTRACTED]
  Sources/NotchAgent/App/NotchAgentApp.swift → windows/NotchAgent.Windows/App.axaml.cs
- `DeskTimestampedTelemetrySample` --references--> `Date`  [EXTRACTED]
  Tests/NotchAgentTests/NotchAgentDeskTests.swift → Sources/NotchAgent/Core/Utilities/Formatters.swift
- `DeskConnectionStateRecorder` --references--> `NotchAgentDeskConnectionState`  [EXTRACTED]
  Tests/NotchAgentTests/NotchAgentDeskTests.swift → Sources/NotchAgent/Features/Desk/NotchAgentDeskProtocol.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **5h Session Limit Tracking** — docs_img_alert_almost_empty_alert_card, docs_img_desktop_burn_burn_projection_chart, docs_img_dashboard_1_claude_code_provider_card [INFERRED 0.75]
- **NotchAgent Popover Carousel Panels** — docs_img_desktop_now_expanded_status_panel, docs_img_panel_burn_burn_rate_projection, docs_img_panel_models_claude_models_panel [INFERRED 0.75]
- **NotchAgent Quota Visualizations** — docs_img_notch_compact_dot_quota_indicator, docs_img_desktop_now_segmented_quota_meter, docs_img_panel_burn_usage_projection_chart [INFERRED 0.75]
- **Swipeable Panel Set (NOW, RHYTHM)** — docs_img_panel_now_now_panel, docs_img_panel_rhythm_rhythm_panel, docs_img_panel_now_page_dots [INFERRED 0.75]
- **Multi-Provider Quota Monitoring** — docs_img_dashboard_1_claude_code_provider_card, docs_img_dashboard_2_gemini_cli_provider_card [INFERRED 0.85]
- **Desk Beta 1 Release Assurance** — docs_notchagent_desk_beta_1_reliability_gates, docs_notchagent_desk_bom_procurement_gate, docs_notchagent_desk_factory_per_unit_qc, docs_notchagent_desk_pilot_acceptance_gates, docs_notchagent_desk_bom_notarized_distribution [INFERRED 0.95]
- **Desk Local-First Privacy Model** — readme_local_first_privacy, docs_notchagent_desk_desk_privacy_boundary, docs_notchagent_desk_onboarding_explicit_mirroring_consent, firmware_notchagent_desk_readme_nonce_authenticated_ram_snapshot, docs_api_account_monitoring_safe_diagnostics [INFERRED 0.95]

## Communities (193 total, 55 thin omitted)

### Community 0 - "NotchExpandedView"
Cohesion: 0.06
Nodes (40): ModelUsage, APIAccountUsage, .id, .reportedSpendBRL, .reportedSpendUSD, .rolling30DaySpendUSD, APIAccountDashboardRow, .id (+32 more)

### Community 1 - "ProviderCardView"
Cohesion: 0.16
Nodes (14): ProviderCardView, .body, .quotaChip, .refreshText, .unavailable, AttentionLevel, Color, GaugeMetric (+6 more)

### Community 2 - "APIAccountFieldOrigins"
Cohesion: 0.10
Nodes (18): APIAccountDataOrigin, derivedFromOfficial, manual, officialAPI, officialPortal, APIAccountFieldOrigins, APIAccountBilling, APIAccountDisplayConfidence (+10 more)

### Community 3 - ".make"
Cohesion: 0.14
Nodes (10): PreferencesStore, .settings, AppSettings, UserDefaults, DeskSnapshotFactory, Dictionary, RefreshState, TokenUsage (+2 more)

### Community 4 - "RefreshScheduler"
Cohesion: 0.07
Nodes (25): UsageProvider, RefreshGenerationTracker, RefreshRequestQueue, RefreshScheduler, Bool, Never, SnapshotStore, Task (+17 more)

### Community 5 - "APIAccountProviderTests"
Cohesion: 0.06
Nodes (8): Set, .apiAccountsExcludedFromTotal, Double, String, APIAccountProviderTests, Double, String, UUID

### Community 6 - ".snapshot"
Cohesion: 0.22
Nodes (6): BlockedCoherenceTests, RestoreMomentTests, Bool, Double, UsageSnapshot, UsageStore

### Community 7 - "SubscriptionStore"
Cohesion: 0.10
Nodes (20): AnyObject, ObservableObject, SubscriptionRepositoryProtocol, SubscriptionStore, .monthlySpend, .summary, Bool, Decimal (+12 more)

### Community 8 - "UsageSnapshot"
Cohesion: 0.10
Nodes (29): CostEstimate, DailyTotal, .id, GaugeMetric, .remaining, HourlyTotal, .id, ModelUsage (+21 more)

### Community 9 - "Settings Window"
Cohesion: 0.06
Nodes (46): Alert: Almost Empty (5h Window) Screenshot, Almost Empty Alert Card, Pixel Space-Invader Mascot, Segmented Quota Progress Bar, Dashboard (Top) Screenshot, Claude Code Provider Card, Hourly Rhythm Bar Chart, Range and Provider Filter Toggle (+38 more)

### Community 10 - "UsageStore"
Cohesion: 0.05
Nodes (49): AnimatablePair, Path, Shape, AppSettings, AttentionLevel, Bool, Double, Int (+41 more)

### Community 11 - "ProviderID"
Cohesion: 0.09
Nodes (30): Comparable, AttentionLevel, critical, .label, normal, warning, Kind, alert (+22 more)

### Community 12 - "MonthlyBudgetStatus"
Cohesion: 0.09
Nodes (24): Int, MonthlyBudgetAlert, MonthlyBudgetLevel, critical, exceeded, normal, warning, MonthlyBudgetStatus (+16 more)

### Community 13 - "AnthropicUsageQuotaReader"
Cohesion: 0.17
Nodes (15): Range, AnthropicUsageQuotaReader, Match, CheckedContinuation, ClaudeQuota, Double, Error, Int (+7 more)

### Community 14 - "NotchAgentDeskSerialTransport"
Cohesion: 0.23
Nodes (8): DeskFrameStreamDecoder, NotchAgentDeskSerialTransport, Data, Int32, Sendable, T, UInt32, UInt8

### Community 15 - "SubscriptionImportParser"
Cohesion: 0.09
Nodes (22): Error, CloudSyncFailure, accountUnavailable, ParseFailure, RawSubscription, SubscriptionImportFormat, csv, json (+14 more)

### Community 16 - "SubscriptionRepository"
Cohesion: 0.11
Nodes (15): SpendDisplayCurrency, brl, .code, usd, SubscriptionRepository, SubscriptionStorePreferences, Bool, Decimal (+7 more)

### Community 17 - ".normalized"
Cohesion: 0.19
Nodes (11): RestoreMoment, .message, AttentionLevel, Bool, Double, Int, Set, String (+3 more)

### Community 18 - "FirecrawlSubscriptionReader"
Cohesion: 0.11
Nodes (18): Currency, brl, usd, FirecrawlSubscriptionReader, RecurringAmount, Bool, Character, CheckedContinuation (+10 more)

### Community 19 - "XDeveloperConsoleReader"
Cohesion: 0.11
Nodes (21): Phase, dashboard, locatingAccount, usage, Bool, CheckedContinuation, Double, Error (+13 more)

### Community 20 - "ChatGPTSubscriptionReader"
Cohesion: 0.11
Nodes (20): ChatGPTSubscriptionReader, Currency, brl, usd, RecurringAmount, .monthlyDecimal, Bool, Character (+12 more)

### Community 21 - "NotchAgent"
Cohesion: 0.06
Nodes (33): NotchAgent 3.1.0 Beta 1, Isolated Per-Account Portal Sessions, Sanitized API Monitoring Diagnostics, Desk Onboarding QR Code, Notarized Desk Distribution Contract, Evidence-Bound Procurement Gate, Desk Beta 1 Verified Core BOM, NotchAgent Desk Architecture (+25 more)

### Community 22 - "NotchAgentDeskCoordinator"
Cohesion: 0.16
Nodes (9): NotchAgentDeskCoordinator, Bool, Never, Task, UsageStore, Void, NotchAgentDeskSoakRecorder, JSONEncoder (+1 more)

### Community 23 - "AISubscription"
Cohesion: 0.11
Nodes (18): AISubscription, .cycleTotalBRL, .monthlyEquivalentBRL, .projectedAnnualBRL, BillingCycle, .id, monthly, yearly (+10 more)

### Community 24 - "NotchAgent.Windows.Models"
Cohesion: 0.10
Nodes (15): NotchAgent.Windows.UI, NotchAgent.Windows.Models, NotchAgent.Windows.Providers.Shared, NotchAgent.Windows.Providers, NotchAgent.Windows.Providers.Codex, NotchAgent.Windows.Providers.Claude, NotchAgent.Windows.Services, UserControl (+7 more)

### Community 25 - "DeskTouch"
Cohesion: 0.09
Nodes (15): DeskTouch, ARDUINO_ISR_ATTR, instance_, interruptPending_, lastPollAtMs_, mux_, pendingAtMicros_, pointPending_ (+7 more)

### Community 26 - "Sendable"
Cohesion: 0.06
Nodes (41): CaseIterable, Identifiable, Sendable, AIExpense, Kind, apiUsage, other, tokenPurchase (+33 more)

### Community 27 - ".report"
Cohesion: 0.13
Nodes (18): AccountRecord, DeskRecord, ProviderRecord, SanitizedDiagnosticExporter, SanitizedDiagnosticReport, AppSettings, Bool, Bundle (+10 more)

### Community 28 - "APIServiceID"
Cohesion: 0.05
Nodes (36): APIServiceID, .addableCases, anthropicAPI, anthropicConsole, artificialAnalysis, brAPI, chatGPTSubscription, .credentialPlaceholder (+28 more)

### Community 29 - "XCTestCase"
Cohesion: 0.12
Nodes (7): ProductIdentityTests, PricingTests, CostLayersTests, DecisionAdvisorTests, AppSettingsCompatibilityTests, ModelBreakdownTests, XCTestCase

### Community 30 - "ProviderId"
Cohesion: 0.10
Nodes (17): JsonSerializerOptions, AppSettings, ThemeMode, AttentionLevel, ProviderHealth, ProviderHealthExtensions, ProviderId, ProviderIdExtensions (+9 more)

### Community 31 - "GoogleSubscriptionReader"
Cohesion: 0.13
Nodes (14): GoogleSubscriptionReader, Bool, Character, CheckedContinuation, Double, Error, Int, Never (+6 more)

### Community 32 - "OpenAIConsoleReader"
Cohesion: 0.13
Nodes (15): OpenAIBalanceStabilizer, OpenAIConsoleReader, Bool, CheckedContinuation, Double, Error, Int, Never (+7 more)

### Community 33 - "OpenRouterConsoleReader"
Cohesion: 0.14
Nodes (15): OpenRouterConsoleReader, OpenRouterSpendStabilizer, Bool, CheckedContinuation, Double, Error, Int, Never (+7 more)

### Community 34 - "String"
Cohesion: 0.05
Nodes (44): Binding, FileManager, updated, CodexOnboardingAction, authenticate, createFirstSession, openInstallGuide, CodexOnboardingInspector (+36 more)

### Community 35 - "ClaudeProvider"
Cohesion: 0.06
Nodes (34): byte, Consumed, CostUsd, End, HourStat, IUsageProvider, ModelStat, object (+26 more)

### Community 36 - ".assess"
Cohesion: 0.19
Nodes (8): DeskReliabilityAcceptance, DeskReliabilityAssessment, DeskTouchContinuityMonitor, Bool, Double, Self, String, UInt32

### Community 37 - "DeskFirmwarePackage"
Cohesion: 0.05
Nodes (43): ClosedRange, CryptoKit, Darwin, Manifest, sha256(), String, UInt32, LocalizedError (+35 more)

### Community 38 - "CodingKeys"
Cohesion: 0.15
Nodes (13): CodingKey, CodingKeys, basePriceBRL, billingCycle, history, id, isActive, nextRenewalDate (+5 more)

### Community 39 - "AnthropicAPIConsoleReader"
Cohesion: 0.14
Nodes (13): AnthropicAPIConsoleReader, Calendar, CheckedContinuation, Double, Error, Int, Never, String (+5 more)

### Community 40 - "NotchAgentDeskTests"
Cohesion: 0.11
Nodes (14): NotchAgentDeskSetupStatus, .canEnableMirroring, .hasLocalProvider, .hasProviderError, .isReady, StepState, actionRequired, ready (+6 more)

### Community 41 - ".testSerialTransportWaitsForHandshakeThenPublishes"
Cohesion: 0.25
Nodes (7): ContinuousClock, DeskConnectionStateRecorder, .last, .telemetrySamples, Data, Duration, Int32

### Community 42 - "AppSettings"
Cohesion: 0.15
Nodes (8): AppSettings, apiAccountIdentifiers, apiAccounts, Bool, Decoder, Double, Int, Set

### Community 43 - "ModelHealth"
Cohesion: 0.15
Nodes (15): ModelHealth, .id, ModelProbeStatus, error, limited, ok, ClaudeQuota, ClaudeQuotaProbe (+7 more)

### Community 44 - "CodingKeys"
Cohesion: 0.09
Nodes (22): CodingKeys, apiAccountMonitoringEnabled, claudeQuotaProbeConsentVersion, claudeQuotaProbeEnabled, claudeSessionTokenBudget, claudeWeeklyTokenBudget, criticalThresholdPercent, fallbackPillEnabled (+14 more)

### Community 45 - "GoogleAIStudioConsoleReader"
Cohesion: 0.17
Nodes (13): GoogleAIStudioConsoleReader, CheckedContinuation, Double, Error, Int, Never, String, Task (+5 more)

### Community 46 - "SubscriptionLedger"
Cohesion: 0.19
Nodes (6): subscriptions, tombstones, SubscriptionLedger, Bool, Int, UUID

### Community 47 - "FloatingBarWindow"
Cohesion: 0.07
Nodes (20): Application, IClassicDesktopStyleApplicationLifetime, NativeMenuItem, PointerPressedEventArgs, TrayIcon, Window, WindowIcon, App (+12 more)

### Community 48 - "APIAccount"
Cohesion: 0.08
Nodes (31): Hashable, OptionSet, APIAccount, APIAccountMoneyKind, balance, remaining, spend, APIAccountReadStatus (+23 more)

### Community 49 - ".findings"
Cohesion: 0.40
Nodes (3): APIAccountOfficialComparator, Decimal, Double

### Community 50 - "XCTest"
Cohesion: 0.13
Nodes (4): AgentMeterCore, NotchAgent, InvoiceImportTests, XCTest

### Community 51 - "TwitterAPIIOConsoleReader"
Cohesion: 0.14
Nodes (14): Any, CheckedContinuation, Data, Double, Error, Int, Never, Task (+6 more)

### Community 52 - "ThemeMode"
Cohesion: 0.17
Nodes (12): ColorScheme, InterfaceLanguage, en, .label, ptBR, ThemeMode, auto, dark (+4 more)

### Community 53 - "RunnerControl"
Cohesion: 0.19
Nodes (11): DateTime, Size, Typeface, Color, DateTimeOffset, DispatcherTimer, double, DrawingContext (+3 more)

### Community 54 - ".value"
Cohesion: 0.23
Nodes (8): Entry, FileScanCache, FileStamp, Sendable, Set, String, URL, Value

### Community 55 - ".Update"
Cohesion: 0.09
Nodes (18): INotifyPropertyChanged, GaugeMetric, DateTimeOffset, Format, Failure, Idle, Refreshing, RefreshState (+10 more)

### Community 56 - "AppEnvironment"
Cohesion: 0.15
Nodes (14): AppEnvironment, Bool, Never, PreferencesStore, RefreshScheduler, SnapshotStore, Task, UsageStore (+6 more)

### Community 57 - ".encode"
Cohesion: 0.25
Nodes (9): CRC32, DeskFrame, DeskFrameCodec, Data, Int, Result, UInt32, UInt8 (+1 more)

### Community 58 - ".preview"
Cohesion: 0.36
Nodes (4): InvoiceImportParser, Data, Decimal, String

### Community 59 - "DeskAmbientRecommendation"
Cohesion: 0.16
Nodes (11): DeskAmbientRecommendation, NotchAgentDeskAmbientIntelligence, Page, burn, .index, models, now, rhythm (+3 more)

### Community 60 - "NotchViewModel"
Cohesion: 0.10
Nodes (22): Edge, NSEvent, Mode, compact, expanded, NotchViewModel, .compactSize, .currentSize (+14 more)

### Community 61 - "View"
Cohesion: 0.14
Nodes (18): PagerDots, .body, RhythmChartView, .body, CGSize, Color, Double, Int (+10 more)

### Community 62 - "ProviderIntegrationTests"
Cohesion: 0.24
Nodes (3): ProviderIntegrationTests, String, URL

### Community 63 - "AnthropicConsoleReader"
Cohesion: 0.16
Nodes (12): AnthropicConsoleReader, CheckedContinuation, Decimal, Error, Int, Never, String, Task (+4 more)

### Community 65 - "SnapshotStore"
Cohesion: 0.28
Nodes (5): SnapshotStore, JSONDecoder, JSONEncoder, URL, UsageSnapshot

### Community 66 - "CloudSyncState"
Cohesion: 0.15
Nodes (13): CKContainer, CKDatabase, CKRecord, CloudKit, CloudSubscriptionSync, CloudSyncState, failed, localOnly (+5 more)

### Community 67 - "NotchWindowController"
Cohesion: 0.11
Nodes (15): NSHostingView, NSPanel, NSPoint, NSRect, NSView, NotchHitTestView, NotchPanel, .canBecomeKey (+7 more)

### Community 68 - "APIAccountCardDropDelegate"
Cohesion: 0.33
Nodes (4): DropDelegate, DropInfo, DropProposal, APIAccountCardDropDelegate

### Community 69 - "SpendingEngine"
Cohesion: 0.25
Nodes (6): SpendingEngine, Bool, Decimal, Double, String, .monthlyBudgetStatus

### Community 70 - "APIAccountProvider"
Cohesion: 0.11
Nodes (11): .url, APIAccountCredentialStore, APIAccountProvider, APIAccountSnapshotCache, GoogleCloudCredentialProvider, AppSettings, Bool, ProviderInstallation (+3 more)

### Community 71 - "APIAccountAuditItem"
Cohesion: 0.18
Nodes (12): APIAccountAuditItem, APIAccountAuditOutcome, blocked, invalid, partial, verified, APIAccountAuditTolerance, APIAccountIntegrityAuditor (+4 more)

### Community 72 - "DeepSeekConsoleReader"
Cohesion: 0.20
Nodes (11): DeepSeekConsoleReader, CheckedContinuation, Error, Int, Never, Task, UUID, Void (+3 more)

### Community 73 - "Desktop NOW Panel Screenshot"
Cohesion: 0.19
Nodes (16): Desktop NOW Panel Screenshot, Carousel Pagination Dots, Expanded Status Panel, Refresh Pause Dashboard Settings Controls, Segmented Quota Meter, Service Quota Card, Compact Notch Bar Screenshot, Compact Notch Bar (+8 more)

### Community 74 - "MenuBarContentView"
Cohesion: 0.12
Nodes (16): Bindable, MenuBarContentView, .costs, .header, .overview, .tabPicker, PreferencesStore, Self (+8 more)

### Community 75 - ".project"
Cohesion: 0.21
Nodes (6): BurnRate, String, TimeInterval, BurnRateTests, Double, PercentSample

### Community 76 - "FullscreenDetector"
Cohesion: 0.25
Nodes (9): DllImport, IntPtr, MonitorInfo, Rect, uint, int, FullscreenDetector, MonitorInfo (+1 more)

### Community 77 - "Foundation"
Cohesion: 0.20
Nodes (4): Combine, Foundation, SwiftUI, WebKit

### Community 78 - "SettingsWindow"
Cohesion: 0.22
Nodes (7): NumericUpDownValueChangedEventArgs, RangeBaseValueChangedEventArgs, SelectionChangedEventArgs, Action, bool, RoutedEventArgs, SettingsWindow

### Community 79 - "desk_protocol.h"
Cohesion: 0.22
Nodes (13): append32(), cobsDecode(), cobsEncode(), crc32(), decodeFrame(), FrameView, payload, payloadLength (+5 more)

### Community 81 - "CodexProvider"
Cohesion: 0.12
Nodes (13): Regex, CancellationToken, DateTimeOffset, Dictionary, ProviderInstallation, string, Task, TimeSpan (+5 more)

### Community 82 - "UsageSnapshot"
Cohesion: 0.25
Nodes (15): long, DateTimeOffset, List, CostEstimate, DailyTotal, HourlyTotal, ModelUsage, SessionUsage (+7 more)

### Community 83 - "CodexProvider"
Cohesion: 0.12
Nodes (8): CodexProvider, ProviderInstallation, TimeInterval, URL, CurrentWindowParityTests, URL, StaleWindowTests, URL

### Community 84 - "WindowRouter"
Cohesion: 0.41
Nodes (7): NSSize, NSWindow, AnyView, String, WindowRouter, .body, .footer

### Community 85 - "SystemIntegration.swift"
Cohesion: 0.24
Nodes (8): ServiceManagement, BundleContext, .isBundledApp, LoginItem, .isAvailable, .isEnabled, Bool, UserNotifications

### Community 86 - "BurnChartView"
Cohesion: 0.12
Nodes (21): Font, NSColor, BurnChartView, .body, .polyline, .span, .visibleSamples, Bool (+13 more)

### Community 87 - ".fromSnapshots"
Cohesion: 0.24
Nodes (8): CostReconciliation, EstimatedCostLayers, ProviderReconciliation, .id, Calendar, Decimal, Double, UsageSnapshot

### Community 90 - ".parseISO8601"
Cohesion: 0.14
Nodes (5): Timestamps, FormatTests, ClaudeParserTests, .fixtureURL, URL

### Community 91 - "NotchGeometry"
Cohesion: 0.15
Nodes (9): NSScreen, PreviewData, Bool, NotchGeometry, Bool, CGFloat, CGRect, CGSize (+1 more)

### Community 92 - "ClaudeProvider"
Cohesion: 0.13
Nodes (12): ClaudeFileStat, ClaudeProvider, .paidProbeAllowed, Bool, ClaudeQuota, ClaudeQuotaProbe, Double, ProviderInstallation (+4 more)

### Community 93 - "ModelPricing"
Cohesion: 0.42
Nodes (5): ModelPricing, PricingTable, Double, String, TokenUsage

### Community 94 - ".snapshot"
Cohesion: 0.33
Nodes (4): Double, UsageSnapshot, UsageStore, ThresholdLifecycleTests

### Community 95 - ".configuration"
Cohesion: 0.23
Nodes (8): Context, NSViewRepresentable, APIAccountPortalLoginView, APIAccountPortalSession, UUID, WKWebView, .body, WKWebViewConfiguration

### Community 96 - "Logger"
Cohesion: 0.39
Nodes (3): string, Log, Logger

### Community 98 - ".snapshot"
Cohesion: 0.29
Nodes (4): StatusAggregatorTests, Double, ProviderHealth, UsageSnapshot

### Community 99 - "IncrementalParseTests"
Cohesion: 0.11
Nodes (13): FileHandle, JSONLReader, Bool, Data, Int, UInt64, URL, Void (+5 more)

### Community 101 - "notchagent-desk-contract-tests.sh"
Cohesion: 0.33
Nodes (9): assert_beta_status_invalid(), assert_bom_rejected(), assert_factory_rejected(), assert_matrix_rejected(), assert_pilot_rejected(), make_factory_telemetry(), make_factory_visual(), make_sample_report() (+1 more)

### Community 103 - "Format"
Cohesion: 0.35
Nodes (4): Format, Double, Int, String

### Community 104 - "DashboardView"
Cohesion: 0.14
Nodes (16): Charts, DashboardView, .body, .controls, .decisionMode, .eventLog, .filteredEvents, .filteredPoints (+8 more)

### Community 105 - "Equatable"
Cohesion: 0.08
Nodes (44): Codable, Equatable, ProviderInstallation, installed, notInstalled, BurnPoint, DeskDeviceTelemetry, DeskHello (+36 more)

### Community 106 - "AccountQuota"
Cohesion: 0.14
Nodes (10): .total, AccountQuota, APIAccountProbe, Any, Data, DateInterval, Int, String (+2 more)

### Community 107 - "ClaudeQuotaProbe"
Cohesion: 0.16
Nodes (11): HttpClient, IReadOnlyDictionary, bool, CancellationToken, DateTimeOffset, Task, TimeSpan, ClaudeQuota (+3 more)

### Community 109 - "ProviderHealth"
Cohesion: 0.13
Nodes (17): ProviderHealth, degraded, .isUsable, noData, notInstalled, ok, parseError, Bool (+9 more)

### Community 110 - "CodexRolloutParser.cs"
Cohesion: 0.16
Nodes (9): ReadOnlyMemory, DateTimeOffset, JsonElement, CodexRateWindow, CodexRolloutParser, CodexTokenInfo, Action, List (+1 more)

### Community 111 - "loop"
Cohesion: 0.16
Nodes (15): alertTouchEvent(), clearData(), dismissDeskAlert(), evaluateDeskAlerts(), handleFrame(), loop(), navEvent(), navigatePage() (+7 more)

### Community 112 - "UsageStore"
Cohesion: 0.09
Nodes (21): EventKind, Guid, DateTimeOffset, EventKind, ProviderAlert, RestoreMoment, ThresholdAlert, UsageEvent (+13 more)

### Community 113 - "NotchAgentDeskBridge.swift"
Cohesion: 0.31
Nodes (7): IOKit, IOKit.serial, deskPaths(), registryInteger(), Int, io_service_t, String

### Community 114 - "createUI"
Cohesion: 0.52
Nodes (7): createAlertOverlay(), createGame(), createUI(), label(), setup(), styleTracking(), surface()

### Community 115 - ".attention"
Cohesion: 0.40
Nodes (5): StatusAggregator, AppSettings, AttentionLevel, ProviderAlert, UsageSnapshot

### Community 116 - "AppUpdateController"
Cohesion: 0.25
Nodes (6): AppUpdateController, .isConfigured, Bool, Bundle, Sparkle, SPUStandardUpdaterController

### Community 117 - "ProviderState"
Cohesion: 0.20
Nodes (10): ProviderState, attention, burn, exhaustEpochMs, id, refresh, remaining, resetEpochMs (+2 more)

### Community 118 - "PrecisionCalibrationTests"
Cohesion: 0.31
Nodes (4): PrecisionCalibrationTests, Int, String, URL

### Community 120 - "NSObject"
Cohesion: 0.22
Nodes (6): Notification, NSApplication, NSApplicationDelegate, NSObject, AppDelegate, Bool

### Community 121 - "Date"
Cohesion: 0.11
Nodes (20): AgentMeterProduct, MetricProvenance, MetricSource, macSync, manual, officialImport, Double, PercentSample (+12 more)

### Community 123 - "SpendingView"
Cohesion: 0.16
Nodes (12): AIExpense.Kind, .label, AIExpense.Source, .label, BRLFormat, SpendingView, .connectedSubscriptions, .connectedSubscriptionsSection (+4 more)

### Community 125 - "CodexParserTests"
Cohesion: 0.15
Nodes (6): URL, CodexParserTests, .fixtureURL, GeminiParserTests, .fixtureURL, URL

### Community 126 - "NotchAgent.Windows.csproj"
Cohesion: 0.25
Nodes (7): net8.0, Avalonia (11.2.5), Avalonia.Desktop (11.2.5), Avalonia.Diagnostics (11.2.5), Avalonia.Fonts.Inter (11.2.5), Avalonia.Themes.Fluent (11.2.5), Microsoft.NET.Sdk

### Community 129 - ".latestUSDToBRL"
Cohesion: 0.24
Nodes (6): BRLExchangeRateService, Calendar, Data, Decimal, URL, URLSession

### Community 130 - "FileStamp"
Cohesion: 0.29
Nodes (6): AppPaths, .appSupport, .home, FileStamp, Int, URL

### Community 131 - "AlertTracker"
Cohesion: 0.25
Nodes (8): AlertTracker, firedMask, id, initialized, lowestRemaining, observed, resetEpochMs, window

### Community 132 - "GaugeLabel"
Cohesion: 0.13
Nodes (18): .footer, .header, GaugeLabel, .body, StatusPill, .body, String, .label (+10 more)

### Community 134 - "Program"
Cohesion: 0.33
Nodes (4): AppBuilder, NotchAgent.Windows, STAThread, Program

### Community 135 - "Decodable"
Cohesion: 0.06
Nodes (45): Decodable, Incident, Payload, StatusPageService, String, TimeInterval, ClaudeFileStat, ClaudeScanCache (+37 more)

### Community 136 - "NotchAgent Desk Validation Pipeline"
Cohesion: 0.33
Nodes (7): Desk Beta 1 Reliability Gates, Firmware 0.6.16 Beta Candidate, Paid Probe Disable Guard, NotchAgent Desk Validation Pipeline, Public Release Security Audit, Fail-Closed Public Release Gate, One-Way Public Repository Sync

### Community 137 - "script.js"
Cohesion: 0.22
Nodes (6): header, recorder, recorderStates, recorderTabs, reveals, year

### Community 144 - "verify-toolchain.sh"
Cohesion: 0.50
Nodes (3): ARDUINO_DIRECTORIES_USER, require_version(), verify-toolchain.sh script

### Community 146 - "audit-public-release.sh"
Cohesion: 0.70
Nodes (4): scan_current(), scan_history(), scan_new_personal_history(), audit-public-release.sh script

### Community 147 - "AlertMomentView"
Cohesion: 0.06
Nodes (30): AlertMomentView, .body, .headline, .message, .pulseSpeed, .severityColor, Color, Double (+22 more)

### Community 149 - "ModelState"
Cohesion: 0.40
Nodes (5): ModelState, latency, name, status, tokens

### Community 154 - "NotchAgent macOS Target"
Cohesion: 0.67
Nodes (4): AgentMeterCore Target, NotchAgent macOS Target, NotchAgentTests Target, NotchAgent XcodeGen Specification

### Community 155 - "notchagent-desk-soak.sh"
Cohesion: 0.83
Nodes (3): cleanup(), fail_soak(), notchagent-desk-soak.sh script

### Community 160 - "Independent API Account Financial Fields"
Cohesion: 0.67
Nodes (3): API Financial Monitoring, Independent API Account Financial Fields, Financial Source Integrity and Reconciliation

### Community 172 - "MenuBarLabelView"
Cohesion: 0.20
Nodes (8): Scene, NotchAgentApp, .body, MenuBarLabelView, .body, .summaryText, .symbolName, String

### Community 205 - ".defaultCandidatePaths"
Cohesion: 0.32
Nodes (3): Int, io_service_t, String

### Community 209 - "notchagent_desk.ino"
Cohesion: 0.16
Nodes (18): alertColor(), alertHeadline(), alertMessage(), attentionColor(), attentionText(), compactTokens(), estimatedEpochMs(), findProvider() (+10 more)

### Community 211 - "SegmentedMeter"
Cohesion: 0.29
Nodes (5): Control, DrawingContext, IBrush, StyledProperty, SegmentedMeter

### Community 212 - "DeskFrameCodecError"
Cohesion: 0.29
Nodes (7): DeskFrameCodecError, incompatibleProtocol, invalidChecksum, invalidCOBS, invalidHeader, invalidLength, payloadTooLarge

### Community 221 - "NotchAgent 3.1.1 — Desk Beta 1"
Cohesion: 0.40
Nodes (4): Beta scope, Highlights, Installation, NotchAgent 3.1.1 — Desk Beta 1

## Knowledge Gaps
- **493 isolated node(s):** `PackageDescription`, `check-github-actions-pins.sh script`, `check-notchagent-desk.sh script`, `ARDUINO_DIRECTORIES_USER`, `check-version.sh script` (+488 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **55 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Date` connect `Date` to `NotchExpandedView`, `.latestUSDToBRL`, `FileStamp`, `.make`, `RefreshScheduler`, `APIAccountProviderTests`, `ProviderCardView`, `SubscriptionStore`, `UsageSnapshot`, `Decodable`, `UsageStore`, `ProviderID`, `.currentBlock`, `AnthropicUsageQuotaReader`, `.snapshot`, `SubscriptionImportParser`, `SubscriptionRepository`, `.normalized`, `FirecrawlSubscriptionReader`, `XDeveloperConsoleReader`, `AISubscription`, `Sendable`, `.report`, `OpenRouterConsoleReader`, `String`, `AnthropicAPIConsoleReader`, `ModelHealth`, `GoogleAIStudioConsoleReader`, `SubscriptionLedger`, `APIAccount`, `TwitterAPIIOConsoleReader`, `.preview`, `DeskAmbientRecommendation`, `ProviderIntegrationTests`, `CloudSyncState`, `APIAccountProvider`, `APIAccountAuditItem`, `.project`, `CodexProvider`, `BurnChartView`, `.parseISO8601`, `ClaudeProvider`, `Format`, `Equatable`, `AccountQuota`, `PrecisionCalibrationTests`?**
  _High betweenness centrality (0.173) - this node is a cross-community bridge._
- **Why does `AccountQuota` connect `AccountQuota` to `APIAccountFieldOrigins`, `APIAccountProviderTests`, `FirecrawlSubscriptionReader`, `XDeveloperConsoleReader`, `ChatGPTSubscriptionReader`, `Sendable`, `APIServiceID`, `GoogleSubscriptionReader`, `OpenAIConsoleReader`, `OpenRouterConsoleReader`, `AnthropicAPIConsoleReader`, `GoogleAIStudioConsoleReader`, `APIAccount`, `.findings`, `TwitterAPIIOConsoleReader`, `AnthropicConsoleReader`, `APIAccountProvider`, `APIAccountAuditItem`, `DeepSeekConsoleReader`, `Equatable`, `Date`?**
  _High betweenness centrality (0.122) - this node is a cross-community bridge._
- **Why does `ClaudeScanCache` connect `ClaudeProvider` to `NotchAgent.Windows.Models`?**
  _High betweenness centrality (0.102) - this node is a cross-community bridge._
- **Are the 10 inferred relationships involving `AccountQuota` (e.g. with `APIAccountFieldOrigins` and `.testDeepSeekMergePrefersConsoleSpendAndAPIBalance()`) actually correct?**
  _`AccountQuota` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `check-github-actions-pins.sh script`, `check-notchagent-desk.sh script` to the rest of the system?**
  _493 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `NotchExpandedView` be split into smaller, more focused modules?**
  _Cohesion score 0.06368011847463902 - nodes in this community are weakly interconnected._
- **Should `APIAccountFieldOrigins` be split into smaller, more focused modules?**
  _Cohesion score 0.10052910052910052 - nodes in this community are weakly interconnected._