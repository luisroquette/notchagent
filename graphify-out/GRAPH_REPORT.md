# Graph Report - /Users/luisroquette/Projects/NotchAgent  (2026-07-23)

## Corpus Check
- 52 files · ~141,503 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1936 nodes · 3963 edges · 150 communities (105 shown, 45 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 270 edges (avg confidence: 0.81)
- Token cost: 0 input · 98,342 output

## Community Hubs (Navigation)
- Notch Theme & Chart Rendering
- Subscription Import & CloudKit Sync
- Claude & Codex Transcript Parsing
- History Store & Refresh Scheduler
- Notch Interaction & Preview Data
- Usage & Cost Models
- Formatting Helpers & Gemini Provider
- Claude Quota Probe (Mac)
- Usage Store & App Settings
- README & Release Docs
- Usage Events Model
- Subscription Store (AgentMeter)
- Subscription Model & Tests
- NOW/Settings/Rhythm Screenshots
- Settings & Subscription Coding Keys
- Windows Namespaces & Theme
- Windows Usage Store & Events
- Provider & Usage Kind Enums
- Windows Runner Control UI
- Subscription & Monthly History
- AgentMeter Home Buttons (iOS)
- AgentMeter Design System (iOS)
- Windows Usage & Snapshot Store
- Burn Rate Projection
- Mixed Test Suite (Invoice/Identity/Aggregator)
- App Settings & Language
- Expense Model & Spending View
- AgentMeter Mobile Root & Typography
- Windows Claude Quota Probe
- Notch Expanded Panel
- Windows Bar Theme & ViewModel
- Subscription Wallet View (iOS)
- Claude Provider (Mac)
- Windows Claude Provider Hour Stats
- Design System Rationale (Motion/Shape/Color)
- Dashboard & Alert Screenshots
- Subscription Editor Views (iOS)
- Renewal Notification Scheduler (iOS)
- Windows Floating Bar Window
- AgentMeter App Imports (Multi-platform)
- Threshold Alerts & Restore Moment
- Menu Bar & Settings Views
- Memory Queries — Product & Quota
- Desktop & Models Panel Screenshots
- Dashboard View (Mac)
- Notch Agent Test Suite Index
- Windows Settings Window
- App Environment & System Integration
- Subscription Store Operations
- CloudKit Subscription Sync
- Windows Fullscreen Detection (P/Invoke)
- Windows Status Aggregator & Preferences
- Notch View Model (Interaction)
- Codex Provider & Capabilities
- Windows Codex Provider
- Spending View (Mac)
- Current Window Parity Tests
- Notch Panel Window
- Cost Layers & Reconciliation
- Notch Window Controller
- Windows App & Tray
- Notch Compact View
- Preferences Store & Blocked Tests
- Dashboard View Helpers
- Review Regression Tests
- Windows Threshold Alerts
- Windows Claude Transcript Parser
- App Delegate (Mac)
- Status Aggregator Tests
- Incremental Parse Tests
- Windows Refresh Scheduler
- Window Router
- Decision Advisor
- AgentMeter Home & Language (iOS)
- Code Signing Fix (make-app.sh)
- Product Identity & Metric Provenance
- JSONL Reader Utility
- Restore Moment Tests
- Windows Codex Rollout Parser
- Windows Formatting Helpers
- Status Aggregator (Mac)
- Rhythm Chart View
- Status Components (Attention/Sparkline)
- Pricing Table (Mac)
- Windows Provider Health
- Windows Usage Provider Interface
- Subscription CSV Template (iOS)
- Windows Project Dependencies (Avalonia)
- Windows Claude Parser Model Stats
- System Integration & Notifications
- App Paths & File Stamp (Mac)
- AgentMeter Mobile UI Tests
- Codex Parser Tests
- Precision Calibration Tests
- Windows App Paths & File Scan
- Windows Logger
- Notch Shape
- Windows Program Entry
- Memory Query — Retro 8-bit Vocabulary
- Windows JSONL Reader
- Alert Moment View
- Windows Refresh State
- App Entry Points (Mac/watchOS)
- Windows Pricing Table
- Theme Mode Application
- Gauge Metric Coherence
- Pixel Glyph Mascot
- Restore Moment View
- Claude Quota Probe Parse Tests
- Windows Tray Icon Factory
- Telemetry Manifest & SpaceX Composition
- Format Tests
- Logging (Mac)
- Watch Currency Formatting
- Menu Bar Label View
- Canvas Color & SpaceX Color Findings
- Design Direction & Principles
- Spacing & Accessibility Rationale
- Package Manifest
- Decoder (singleton)
- Boarding Pass Component
- Command Bar Component
- Cost Hero Component
- Critical Red Color Token
- Event Rail Component
- Ink Color Token
- Nominal Green Color Token
- Pixel Rail Component
- Primary Action Button
- Provider Telemetry Component
- Section Header Component
- Status Chip Component
- Surface & Elevated Color Tokens
- Warning Amber Color Token
- Brand Personality (Product)
- Target Users (Product)
- make-app.sh Packaging (README)
- Scene Type Reference
- Refresh Scheduler Reference
- Snapshot Store Reference
- AnyView Type Reference
- App Settings Reference
- Provider Alert Reference
- Restore Moment Reference
- Usage Event Reference
- String Type Reference
- Gauge Metric Reference
- Quota Status Reference
- Time Interval Reference
- SpaceX Motion Audit

## God Nodes (most connected - your core abstractions)
1. `SubscriptionStore` - 75 edges
2. `Date` - 71 edges
3. `AISubscription` - 64 edges
4. `Foundation` - 41 edges
5. `ProviderID` - 39 edges
6. `AgentMeterProvider` - 35 edges
7. `UsageStore` - 34 edges
8. `SwiftUI` - 33 edges
9. `UsageStore` - 31 edges
10. `AIExpense` - 30 edges

## Surprising Connections (you probably didn't know these)
- `MarketOrbit.jpg — sci-fi orbital trading dashboard mockup (Earth view, telemetry HUD panels, market feed/portfolio summary)` --semantically_similar_to--> `SpaceX audit — Composition (full-viewport scenes, no card elevation)`  [INFERRED] [semantically similar]
  Resources/iOS/MarketOrbit.jpg → SPACEX_STYLE_AUDIT.md
- `Shared JSONL Parsers / Calibrated Logic` --semantically_similar_to--> `UsageProvider Plugin Pattern`  [INFERRED] [semantically similar]
  windows/README.md → README.md
- `Memory query — reusing 8-bit retro vocabulary for iOS, excluding GAME OVER/runner for calm factual data` --semantically_similar_to--> `Pixel Companion — procedural 8-bit mascot as health indicator`  [INFERRED] [semantically similar]
  graphify-out/memory/query_20260718_020046_trazer_referências_funcionais_de_jogos_clássicos_8.md → DESIGN.md
- `Memory query — reusing 8-bit retro vocabulary for iOS, excluding GAME OVER/runner for calm factual data` --semantically_similar_to--> `Segmented Gauge — each block is a real item, never decorative`  [INFERRED] [semantically similar]
  graphify-out/memory/query_20260718_020046_trazer_referências_funcionais_de_jogos_clássicos_8.md → DESIGN.md
- `Anti-references — avoid generic SaaS dashboard, gamer neon, space fantasy, hostile terminal` --semantically_similar_to--> `AgentMeter translation guidance — Apply/Preserve/Avoid rules`  [INFERRED] [semantically similar]
  PRODUCT.md → SPACEX_STYLE_AUDIT.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Claude/Codex/Gemini provider trio — shared quota-provider abstraction compared for confidence** — sources_agentmetercore_claudeprovider, sources_agentmetercore_codexprovider, sources_agentmetercore_geminiprovider [INFERRED 0.85]
- **AgentMeter design tokens translated from SpaceX audit (color, type, shape)** — design_signal_blue, design_provider_colors, resources_ios_fonts_font_licenses_d_din, resources_ios_fonts_font_licenses_roboto_mono, design_shape [INFERRED 0.85]
- **Retro 8-bit vocabulary reused across macOS notch and iOS/mobile design** — sources_agentmetercore_pixelglyph, sources_agentmetercore_segmentedmeter, sources_agentmetercore_theme, sources_notchagent_notchrunnerview, design_pixel_companion, design_segmented_gauge [INFERRED 0.85]
- **Provider-to-UI Data Flow Pipeline** — readme_usage_provider_plugin, readme_usage_snapshot, readme_usage_store, readme_notch_overlay, readme_menu_bar, readme_dashboard [EXTRACTED 0.90]
- **Three Usage Providers** — readme_claude_provider, readme_codex_provider, readme_gemini_provider [EXTRACTED 0.90]
- **Pure Tested Computation Core** — readme_status_aggregator, readme_threshold_alerts, readme_burn_rate [EXTRACTED 0.85]
- **Multi-Provider Quota Monitoring** — docs_img_dashboard_1_claude_code_provider_card, docs_img_dashboard_2_codex_provider_card, docs_img_dashboard_2_gemini_cli_provider_card [INFERRED 0.85]
- **5h Session Limit Tracking** — docs_img_alert_almost_empty_alert_card, docs_img_desktop_burn_burn_projection_chart, docs_img_dashboard_1_claude_code_provider_card [INFERRED 0.75]
- **NotchAgent Popover Carousel Panels** — docs_img_desktop_now_expanded_status_panel, docs_img_panel_burn_burn_rate_projection, docs_img_panel_models_claude_models_panel [INFERRED 0.75]
- **NotchAgent Quota Visualizations** — docs_img_notch_compact_dot_quota_indicator, docs_img_desktop_now_segmented_quota_meter, docs_img_panel_burn_usage_projection_chart [INFERRED 0.75]
- **Swipeable Panel Set (NOW, RHYTHM)** — docs_img_panel_now_now_panel, docs_img_panel_rhythm_rhythm_panel, docs_img_panel_now_page_dots [INFERRED 0.75]

## Communities (150 total, 45 thin omitted)

### Community 0 - "Notch Theme & Chart Rendering"
Cohesion: 0.06
Nodes (45): ColorScheme, NSColor, Path, BurnChartView, Bool, CGFloat, CGSize, Double (+37 more)

### Community 1 - "Subscription Import & CloudKit Sync"
Cohesion: 0.05
Nodes (39): CloudKit, Error, Locale, Error, Result, CloudSyncFailure, accountUnavailable, CloudSyncState (+31 more)

### Community 2 - "Claude & Codex Transcript Parsing"
Cohesion: 0.07
Nodes (42): Decodable, ClaudeFileStat, ClaudeScanCache, ClaudeTranscriptParser, Entry, HourStat, Line, Message (+34 more)

### Community 3 - "History Store & Refresh Scheduler"
Cohesion: 0.07
Nodes (25): JSONEncoder, UsageProvider, RefreshScheduler, Bool, Never, SnapshotStore, Task, UsageStore (+17 more)

### Community 4 - "Notch Interaction & Preview Data"
Cohesion: 0.08
Nodes (21): Edge, NSEvent, NSScreen, PreviewData, Bool, NotchViewModel, Bool, CGFloat (+13 more)

### Community 5 - "Usage & Cost Models"
Cohesion: 0.17
Nodes (24): Codable, Equatable, Identifiable, CostEstimate, DailyTotal, HourlyTotal, ModelHealth, ModelUsage (+16 more)

### Community 6 - "Formatting Helpers & Gemini Provider"
Cohesion: 0.08
Nodes (16): Format, Double, Int, String, Timestamps, Entry, GeminiLogParser, String (+8 more)

### Community 7 - "Claude Quota Probe (Mac)"
Cohesion: 0.12
Nodes (20): QuotaStatus, Security, ClaudeQuota, ClaudeQuotaProbe, ClaudeTokenLocator, Data, Date, Double (+12 more)

### Community 8 - "Usage Store & App Settings"
Cohesion: 0.12
Nodes (19): AppSettings, AttentionLevel, Bool, Double, Int, Never, PercentSample, PreferencesStore (+11 more)

### Community 9 - "README & Release Docs"
Cohesion: 0.07
Nodes (32): Retro Hardware Gauge Design System, Release 1.0.0, anthropic-ratelimit-unified-* Headers, BurnRate Projection, Claude Code Provider, Claude Quota Probe, Codex Provider (Rollouts), Dashboard (Swift Charts) (+24 more)

### Community 10 - "Usage Events Model"
Cohesion: 0.12
Nodes (28): CaseIterable, Comparable, Sendable, Source, localEstimate, manual, officialInvoice, AttentionLevel (+20 more)

### Community 11 - "Subscription Store (AgentMeter)"
Cohesion: 0.14
Nodes (16): Never, ObservableObject, AgentMeterMobileApp, Scene, SpendDisplayCurrency, brl, usd, SubscriptionStore (+8 more)

### Community 12 - "Subscription Model & Tests"
Cohesion: 0.14
Nodes (13): AISubscription, BillingCycle, monthly, yearly, SubscriptionSummary, Bool, Calendar, Date (+5 more)

### Community 13 - "NOW/Settings/Rhythm Screenshots"
Cohesion: 0.09
Nodes (29): NotchAgent NOW Panel Screenshot, Burn Rate and Runs-Out Projection, Claude Provider Card, Codex Provider Card, Gemini Not Installed Row, NOW Panel, Panel Page Dots Navigation, Panel Toolbar (Refresh, Pause, Dashboard, Settings) (+21 more)

### Community 14 - "Settings & Subscription Coding Keys"
Cohesion: 0.07
Nodes (28): CodingKey, CodingKeys, basePriceBRL, billingCycle, history, id, isActive, nextRenewalDate (+20 more)

### Community 15 - "Windows Namespaces & Theme"
Cohesion: 0.13
Nodes (11): NotchAgent.Windows.UI, NotchAgent.Windows.Models, NotchAgent.Windows.Providers.Shared, NotchAgent.Windows.Providers, NotchAgent.Windows.Providers.Codex, NotchAgent.Windows.Providers.Claude, NotchAgent.Windows.Services, UserControl (+3 more)

### Community 16 - "Windows Usage Store & Events"
Cohesion: 0.15
Nodes (14): EventKind, Guid, DateTimeOffset, EventKind, ProviderAlert, RestoreMoment, ThresholdAlert, UsageEvent (+6 more)

### Community 17 - "Provider & Usage Kind Enums"
Cohesion: 0.08
Nodes (25): Self, Kind, apiUsage, other, tokenPurchase, usageCredits, ProviderHealth, degraded (+17 more)

### Community 18 - "Windows Runner Control UI"
Cohesion: 0.13
Nodes (16): Control, DateTime, Size, Typeface, Color, DateTimeOffset, DispatcherTimer, double (+8 more)

### Community 19 - "Subscription & Monthly History"
Cohesion: 0.12
Nodes (18): FinancialHistory, MonthlyProviderSpend, Calendar, Date, Decimal, Int, String, Array (+10 more)

### Community 20 - "AgentMeter Home Buttons (iOS)"
Cohesion: 0.11
Nodes (15): ButtonStyle, CGSize, AgentMeterPrimaryButtonStyle, AgentMeterSecondaryButtonStyle, AgentMeterTheme, Color, Configuration, MissionArcadeView (+7 more)

### Community 21 - "AgentMeter Design System (iOS)"
Cohesion: 0.14
Nodes (21): Content, AgentMeterBrandMark, AgentMeterOrbitMark, AgentMeterPanel, AgentMeterPixelCompanion, AgentMeterPixelRail, AgentMeterProviderBadge, AgentMeterSectionHeader (+13 more)

### Community 22 - "Windows Usage & Snapshot Store"
Cohesion: 0.15
Nodes (20): JsonSerializerOptions, long, DateTimeOffset, List, CostEstimate, DailyTotal, GaugeMetric, HourlyTotal (+12 more)

### Community 23 - "Burn Rate Projection"
Cohesion: 0.18
Nodes (12): BurnRate, PercentSample, Projection, Double, String, TimeInterval, Date, GeminiLogStat (+4 more)

### Community 24 - "Mixed Test Suite (Invoice/Identity/Aggregator)"
Cohesion: 0.08
Nodes (8): InvoiceImportTests, ProductIdentityTests, PricingTests, DecisionAdvisorTests, AppSettingsCompatibilityTests, ModelBreakdownTests, ThresholdAlertsTests, XCTestCase

### Community 25 - "App Settings & Language"
Cohesion: 0.11
Nodes (16): AppSettings, InterfaceLanguage, en, ptBR, Bool, Decoder, Double, Int (+8 more)

### Community 26 - "Expense Model & Spending View"
Cohesion: 0.17
Nodes (15): AIExpense, MonthlyBudgetAlert, MonthlyBudgetLevel, critical, exceeded, normal, warning, MonthlyBudgetStatus (+7 more)

### Community 27 - "AgentMeter Mobile Root & Typography"
Cohesion: 0.23
Nodes (8): Font, HorizontalAlignment, Indicator, AgentMeterTypography, MobileRootView, Double, LocalizedStringKey, String

### Community 28 - "Windows Claude Quota Probe"
Cohesion: 0.16
Nodes (11): HttpClient, IReadOnlyDictionary, bool, CancellationToken, DateTimeOffset, Task, TimeSpan, ClaudeQuota (+3 more)

### Community 29 - "Notch Expanded Panel"
Cohesion: 0.19
Nodes (11): BurnRate, ModelUsage, NotchExpandedView, Bool, Color, Double, Int, ModelHealth (+3 more)

### Community 30 - "Windows Bar Theme & ViewModel"
Cohesion: 0.18
Nodes (10): INotifyPropertyChanged, Color, IBrush, AppTheme, Color, DateTimeOffset, IBrush, BarViewModel (+2 more)

### Community 31 - "Subscription Wallet View (iOS)"
Cohesion: 0.21
Nodes (6): brl(), SubscriptionWalletView, Color, LocalizedStringKey, String, UNAuthorizationStatus

### Community 32 - "Claude Provider (Mac)"
Cohesion: 0.14
Nodes (12): ClaudeFileStat, ClaudeProvider, AppSettings, ClaudeQuota, ClaudeQuotaProbe, Double, ProviderInstallation, String (+4 more)

### Community 33 - "Windows Claude Provider Hour Stats"
Cohesion: 0.13
Nodes (14): CostUsd, End, HourStat, Start, Tokens, CancellationToken, DateTimeOffset, Dictionary (+6 more)

### Community 34 - "Design System Rationale (Motion/Shape/Color)"
Cohesion: 0.13
Nodes (18): Motion rules — no load choreography, 150-240ms states, reduce-motion support, Provider colors — small identifiers for Claude/ChatGPT/Gemini, Shape rules — 4pt functional radii, hairline dividers, Signal Blue (#2D8CFF) — primary action color, Typography system (D-DIN + Roboto Mono), Anti-references — avoid generic SaaS dashboard, gamer neon, space fantasy, hostile terminal, AgentMeterCore target — shared framework (iOS/macOS/watchOS), AgentMeterCoreTests target (+10 more)

### Community 35 - "Dashboard & Alert Screenshots"
Cohesion: 0.18
Nodes (18): Alert: Almost Empty (5h Window) Screenshot, Almost Empty Alert Card, Pixel Space-Invader Mascot, Segmented Quota Progress Bar, Dashboard (Top) Screenshot, Claude Code Provider Card, Hourly Rhythm Bar Chart, Range and Provider Filter Toggle (+10 more)

### Community 36 - "Subscription Editor Views (iOS)"
Cohesion: 0.15
Nodes (13): CGFloat, QuickSubscriptionEditorView, SubscriptionEditorView, SubscriptionImportReviewView, Bool, Decimal, Int, WalletTelemetry (+5 more)

### Community 37 - "Renewal Notification Scheduler (iOS)"
Cohesion: 0.18
Nodes (6): RenewalNotificationScheduler, Bool, String, UNAuthorizationStatus, UUID, Task

### Community 38 - "Windows Floating Bar Window"
Cohesion: 0.16
Nodes (7): PointerPressedEventArgs, Action, bool, CancellationTokenSource, DispatcherTimer, RoutedEventArgs, FloatingBarWindow

### Community 39 - "AgentMeter App Imports (Multi-platform)"
Cohesion: 0.18
Nodes (5): AgentMeterCore, Charts, WatchRootView, NotchContainerView, SwiftUI

### Community 40 - "Threshold Alerts & Restore Moment"
Cohesion: 0.26
Nodes (9): RestoreMoment, AttentionLevel, Bool, Double, Int, Set, String, ThresholdAlert (+1 more)

### Community 41 - "Menu Bar & Settings Views"
Cohesion: 0.20
Nodes (10): Bindable, Binding, MenuBarContentView, PreferencesStore, ProviderID, UsageSnapshot, SettingsView, Int (+2 more)

### Community 42 - "Memory Queries — Product & Quota"
Cohesion: 0.19
Nodes (16): Content voice rules — label data as Oficial/informado/estimado, Memory query — 'relembre o projeto NotchAgent' (product overview), Memory query — quota estimation mechanism (Claude probe, Codex rollout, Gemini unavailable, burn rate), Memory query — confidence comparison, Mac quota estimate vs standalone iOS estimator, Product Purpose — personal control center for AI services, distinguishing official/informed/estimated data, BurnRate — linear projection from recent percent samples, ClaudeProvider (code symbol referenced in memory queries), ClaudeQuotaProbe — one-token probe reading Anthropic 5h/7d headers (+8 more)

### Community 43 - "Desktop & Models Panel Screenshots"
Cohesion: 0.19
Nodes (16): Desktop NOW Panel Screenshot, Carousel Pagination Dots, Expanded Status Panel, Refresh Pause Dashboard Settings Controls, Segmented Quota Meter, Service Quota Card, Compact Notch Bar Screenshot, Compact Notch Bar (+8 more)

### Community 45 - "Notch Agent Test Suite Index"
Cohesion: 0.20
Nodes (7): NumericUpDownValueChangedEventArgs, RangeBaseValueChangedEventArgs, SelectionChangedEventArgs, Action, bool, RoutedEventArgs, SettingsWindow

### Community 46 - "Windows Settings Window"
Cohesion: 0.20
Nodes (11): ProviderAlert, RefreshScheduler, RestoreMoment, SnapshotStore, AppEnvironment, HistoryStore, NotchViewModel, PreferencesStore (+3 more)

### Community 48 - "Subscription Store Operations"
Cohesion: 0.23
Nodes (6): CKContainer, CKDatabase, CKRecord, CloudSubscriptionSync, String, SubscriptionSyncSnapshot

### Community 49 - "CloudKit Subscription Sync"
Cohesion: 0.25
Nodes (9): DllImport, IntPtr, MonitorInfo, Rect, uint, int, FullscreenDetector, MonitorInfo (+1 more)

### Community 50 - "Windows Fullscreen Detection (P/Invoke)"
Cohesion: 0.21
Nodes (8): AppSettings, ThemeMode, AttentionLevel, PreferencesStore, Dictionary, IEnumerable, List, StatusAggregator

### Community 51 - "Windows Status Aggregator & Preferences"
Cohesion: 0.19
Nodes (7): AppKit, Combine, Foundation, Observation, Mode, compact, expanded

### Community 52 - "Notch View Model (Interaction)"
Cohesion: 0.18
Nodes (8): Hashable, OptionSet, ProviderCapabilities, Int, CodexProvider, ProviderInstallation, TimeInterval, URL

### Community 53 - "Codex Provider & Capabilities"
Cohesion: 0.19
Nodes (10): IUsageProvider, Regex, CancellationToken, DateTimeOffset, Dictionary, ProviderInstallation, string, Task (+2 more)

### Community 54 - "Windows Codex Provider"
Cohesion: 0.21
Nodes (9): AIExpense.Kind, AIExpense.Source, BRLFormat, PlanEditor, SpendingView, Color, Decimal, String (+1 more)

### Community 55 - "Spending View (Mac)"
Cohesion: 0.14
Nodes (5): CurrentWindowParityTests, URL, StaleWindowTests, URL, UUID

### Community 56 - "Current Window Parity Tests"
Cohesion: 0.15
Nodes (10): NSHostingView, NSPanel, NSPoint, NSRect, NSView, NotchHitTestView, NotchPanel, AnyView (+2 more)

### Community 57 - "Notch Panel Window"
Cohesion: 0.21
Nodes (9): CostReconciliation, EstimatedCostLayers, ProviderReconciliation, Calendar, Decimal, Double, ProviderID, UsageSnapshot (+1 more)

### Community 58 - "Cost Layers & Reconciliation"
Cohesion: 0.27
Nodes (5): Any, NotchPanel, NotchWindowController, NotchViewModel, UsageStore

### Community 59 - "Notch Window Controller"
Cohesion: 0.24
Nodes (5): Application, IClassicDesktopStyleApplicationLifetime, NativeMenuItem, TrayIcon, App

### Community 60 - "Windows App & Tray"
Cohesion: 0.30
Nodes (7): GaugeMetric, NotchCompactView, Bool, Color, ProviderID, String, UsageSnapshot

### Community 61 - "Notch Compact View"
Cohesion: 0.24
Nodes (6): PreferencesStore, AppSettings, BlockedCoherenceTests, Double, UsageSnapshot, UsageStore

### Community 62 - "Preferences Store & Blocked Tests"
Cohesion: 0.36
Nodes (6): DashboardView, HistoryStore, Int, ProviderID, String, UsageSnapshot

### Community 63 - "Dashboard View Helpers"
Cohesion: 0.35
Nodes (4): Double, UsageSnapshot, UsageStore, ThresholdLifecycleTests

### Community 64 - "Review Regression Tests"
Cohesion: 0.18
Nodes (6): AttentionLevel, double, HashSet, int, ThresholdAlert, ThresholdAlerts

### Community 65 - "Windows Threshold Alerts"
Cohesion: 0.24
Nodes (7): byte, Consumed, ReadOnlySpan, Stat, DateTimeOffset, JsonElement, ClaudeTranscriptParser

### Community 66 - "Windows Claude Transcript Parser"
Cohesion: 0.18
Nodes (7): Notification, NSApplication, NSApplicationDelegate, NSObject, AppDelegate, Bool, UsageEvent

### Community 67 - "App Delegate (Mac)"
Cohesion: 0.29
Nodes (4): StatusAggregatorTests, Double, ProviderHealth, UsageSnapshot

### Community 68 - "Status Aggregator Tests"
Cohesion: 0.29
Nodes (4): IncrementalParseTests, Int, String, URL

### Community 69 - "Incremental Parse Tests"
Cohesion: 0.25
Nodes (6): bool, CancellationToken, CancellationTokenSource, List, Task, RefreshScheduler

### Community 70 - "Windows Refresh Scheduler"
Cohesion: 0.51
Nodes (5): AnyView, NSSize, NSWindow, String, WindowRouter

### Community 71 - "Window Router"
Cohesion: 0.22
Nodes (8): Int, DecisionAdvisor, Severity, critical, normal, warning, ProviderID, UsageSnapshot

### Community 72 - "Decision Advisor"
Cohesion: 0.27
Nodes (7): AgentMeterHomeView, String, Void, AppLanguage, english, portuguese, LanguageFlagView

### Community 73 - "AgentMeter Home & Language (iOS)"
Cohesion: 0.29
Nodes (8): App Bundle Assembly, Apple Development Identity (K74FG72F9W / Team S3YCFYY8SC), Code Signing, Icon Generation, Keychain ACL Persistence (Always Allow grant), make-app.sh script (main routine), Ad-hoc → Stable Identity Signing Fix, NotchAgent v1.0.1 release

### Community 74 - "Code Signing Fix (make-app.sh)"
Cohesion: 0.29
Nodes (8): AgentMeterProduct, MetricProvenance, MetricSource, macSync, manual, officialImport, Date, Double

### Community 75 - "Product Identity & Metric Provenance"
Cohesion: 0.27
Nodes (7): JSONLReader, Bool, Data, Int, UInt64, URL, Void

### Community 77 - "Restore Moment Tests"
Cohesion: 0.36
Nodes (5): DateTimeOffset, JsonElement, CodexRateWindow, CodexRolloutParser, CodexTokenInfo

### Community 79 - "Windows Formatting Helpers"
Cohesion: 0.47
Nodes (5): StatusAggregator, AppSettings, AttentionLevel, ProviderAlert, UsageSnapshot

### Community 80 - "Status Aggregator (Mac)"
Cohesion: 0.33
Nodes (6): PagerDots, RhythmChartView, CGSize, Color, Double, Int

### Community 81 - "Rhythm Chart View"
Cohesion: 0.36
Nodes (8): AttentionDot, AttentionLevel, ProviderHealth, SparklineView, Color, Double, String, UsageBar

### Community 82 - "Status Components (Attention/Sparkline)"
Cohesion: 0.42
Nodes (5): ModelPricing, PricingTable, Double, String, TokenUsage

### Community 83 - "Pricing Table (Mac)"
Cohesion: 0.28
Nodes (4): ProviderHealth, ProviderHealthExtensions, ProviderIdExtensions, QuotaStatus

### Community 84 - "Windows Provider Health"
Cohesion: 0.25
Nodes (5): CancellationToken, Task, IUsageProvider, ProviderInstallation, ProviderInstallationKind

### Community 85 - "Windows Usage Provider Interface"
Cohesion: 0.25
Nodes (6): FileDocument, FileWrapper, SubscriptionCSVTemplateDocument, ReadConfiguration, UTType, WriteConfiguration

### Community 86 - "Subscription CSV Template (iOS)"
Cohesion: 0.25
Nodes (7): net8.0, Avalonia (11.2.5), Avalonia.Desktop (11.2.5), Avalonia.Diagnostics (11.2.5), Avalonia.Fonts.Inter (11.2.5), Avalonia.Themes.Fluent (11.2.5), Microsoft.NET.Sdk

### Community 87 - "Windows Project Dependencies (Avalonia)"
Cohesion: 0.32
Nodes (6): ModelStat, object, Dictionary, HashSet, ClaudeFileStat, ClaudeScanCache

### Community 88 - "Windows Claude Parser Model Stats"
Cohesion: 0.32
Nodes (5): ServiceManagement, BundleContext, LoginItem, Bool, UserNotifications

### Community 89 - "System Integration & Notifications"
Cohesion: 0.36
Nodes (6): AppPaths, FileStamp, recentFiles(), Int, String, URL

### Community 90 - "App Paths & File Stamp (Mac)"
Cohesion: 0.36
Nodes (3): AgentMeterMobileUITests, String, XCUIApplication

### Community 91 - "AgentMeter Mobile UI Tests"
Cohesion: 0.25
Nodes (3): CodexParserTests, GeminiParserTests, URL

### Community 92 - "Codex Parser Tests"
Cohesion: 0.36
Nodes (4): PrecisionCalibrationTests, Int, String, URL

### Community 93 - "Precision Calibration Tests"
Cohesion: 0.25
Nodes (5): DateTimeOffset, List, AppPaths, FileScan, FileStamp

### Community 94 - "Windows App Paths & File Scan"
Cohesion: 0.39
Nodes (3): string, Log, Logger

### Community 95 - "Windows Logger"
Cohesion: 0.29
Nodes (5): AnimatablePair, Shape, NotchShape, CGFloat, CGRect

### Community 96 - "Notch Shape"
Cohesion: 0.33
Nodes (4): AppBuilder, NotchAgent.Windows, STAThread, Program

### Community 97 - "Windows Program Entry"
Cohesion: 0.29
Nodes (7): Pixel Companion — procedural 8-bit mascot as health indicator, Segmented Gauge — each block is a real item, never decorative, Memory query — reusing 8-bit retro vocabulary for iOS, excluding GAME OVER/runner for calm factual data, PixelGlyph — procedural pixel companion sprite, SegmentedMeter — truthful segmented-meter component, Theme (code symbol referenced in memory queries), NotchRunnerView (excluded retro runner animation, code symbol)

### Community 98 - "Memory Query — Retro 8-bit Vocabulary"
Cohesion: 0.33
Nodes (4): ReadOnlyMemory, Action, List, JsonlReader

### Community 99 - "Windows JSONL Reader"
Cohesion: 0.29
Nodes (6): AlertMomentView, Color, Double, String, ThresholdAlert, Void

### Community 100 - "Alert Moment View"
Cohesion: 0.52
Nodes (6): Failure, Idle, PercentSample, Refreshing, RefreshState, Success

### Community 101 - "Windows Refresh State"
Cohesion: 0.33
Nodes (5): App, AgentMeterWatchApp, Scene, NotchAgentApp, Scene

### Community 102 - "App Entry Points (Mac/watchOS)"
Cohesion: 0.47
Nodes (3): string, ModelPricing, PricingTable

### Community 104 - "Theme Mode Application"
Cohesion: 0.50
Nodes (3): GaugeMetric, Bool, UsageSnapshot

### Community 105 - "Gauge Metric Coherence"
Cohesion: 0.40
Nodes (4): PixelGlyph, Color, Double, Int

### Community 106 - "Pixel Glyph Mascot"
Cohesion: 0.40
Nodes (4): RestoreMomentView, Double, RestoreMoment, Void

### Community 108 - "Claude Quota Probe Parse Tests"
Cohesion: 0.40
Nodes (3): WindowIcon, Color, TrayIconFactory

### Community 109 - "Windows Tray Icon Factory"
Cohesion: 0.50
Nodes (4): Provider Manifest component (hairline list, no card grid), Telemetry Manifest component, MarketOrbit.jpg — sci-fi orbital trading dashboard mockup (Earth view, telemetry HUD panels, market feed/portfolio summary), SpaceX audit — Composition (full-viewport scenes, no card elevation)

### Community 112 - "Logging (Mac)"
Cohesion: 0.67
Nodes (3): Decimal, String, watchBRL()

## Knowledge Gaps
- **189 isolated node(s):** `os`, `Log`, `normal`, `warning`, `critical` (+184 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **45 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Window` connect `Claude & Codex Transcript Parsing` to `Notch Agent Test Suite Index`, `Windows Floating Bar Window`?**
  _High betweenness centrality (0.248) - this node is a cross-community bridge._
- **Why does `Foundation` connect `Windows Status Aggregator & Preferences` to `Subscription Import & CloudKit Sync`, `Claude & Codex Transcript Parsing`, `History Store & Refresh Scheduler`, `Notch Interaction & Preview Data`, `Usage & Cost Models`, `Formatting Helpers & Gemini Provider`, `Claude Quota Probe (Mac)`, `Usage Events Model`, `Subscription Model & Tests`, `Provider & Usage Kind Enums`, `Subscription & Monthly History`, `Burn Rate Projection`, `App Settings & Language`, `Expense Model & Spending View`, `Claude Provider (Mac)`, `Threshold Alerts & Restore Moment`, `Windows Settings Window`, `Notch View Model (Interaction)`, `Notch Panel Window`, `Window Router`, `Decision Advisor`, `Code Signing Fix (make-app.sh)`, `Product Identity & Metric Provenance`, `Status Components (Attention/Sparkline)`, `System Integration & Notifications`?**
  _High betweenness centrality (0.160) - this node is a cross-community bridge._
- **Why does `SettingsWindow` connect `Notch Agent Test Suite Index` to `Claude & Codex Transcript Parsing`, `Notch Window Controller`, `Windows Fullscreen Detection (P/Invoke)`?**
  _High betweenness centrality (0.130) - this node is a cross-community bridge._
- **Are the 5 inferred relationships involving `SubscriptionStore` (e.g. with `AgentMeterWatchApp` and `.testHistoryRecordsRenewalPriceChangeAndCancellation()`) actually correct?**
  _`SubscriptionStore` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 16 inferred relationships involving `Date` (e.g. with `.handleScroll()` and `.fetchSnapshot()`) actually correct?**
  _`Date` has 16 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `AISubscription` (e.g. with `.init()` and `.testImportSkipsExistingAndRepeatedPlans()`) actually correct?**
  _`AISubscription` has 15 INFERRED edges - model-reasoned connections that need verification._
- **What connects `os`, `Log`, `normal` to the rest of the system?**
  _196 weakly-connected nodes found - possible documentation gaps or missing edges._