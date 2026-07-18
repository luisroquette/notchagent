# Graph Report - .  (2026-07-16)

## Corpus Check
- 121 files · ~120,685 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1364 nodes · 2712 edges · 91 communities (83 shown, 8 thin omitted)
- Extraction: 93% EXTRACTED · 7% INFERRED · 0% AMBIGUOUS · INFERRED: 188 edges (avg confidence: 0.8)
- Token cost: 318,627 input · 0 output

## Community Hubs (Navigation)
- Provider Protocol & Scheduler
- Claude Transcript Parsing
- Preferences & Snapshot Persistence
- Usage & Cost Models
- Burn Chart Rendering
- Docs & Design Rationale
- Claude Quota Probe (Mac)
- Settings & Attention Types
- NOW Panel UI (Screenshots)
- Theme & Settings Enums
- Windows Runner Control
- Burn Rate Projection
- Menu Bar & Alert Views
- Notch View Model (Interaction)
- Windows Theme & Brushes
- Mac Theme & Gauge Labels
- Preview Data & Notch Geometry
- App Environment & System Integration
- Windows Settings & Fetch
- Compact Notch View
- Windows Usage Totals
- Alert & Dashboard UI (Screenshots)
- Windows Floating Bar Window
- Windows Quota HTTP Probe
- Expanded Notch Panel Body
- Threshold Alerts & Restore Moment
- Codex & Gemini Parser Tests
- Windows Usage Store
- App Bootstrap & Frameworks
- Desktop Panel & Notch (Screenshots)
- Provider Model & Capabilities
- Windows Provider Model
- Notch Panel Window
- App Paths & File Stamp (Mac)
- Windows Namespaces
- Windows Provider Probes
- Settings Decoding & Integration Tests
- Windows Fullscreen Detection (P/Invoke)
- Mac Test Suite Base
- Windows Settings Window
- Menu Bar Content & Status
- Settings Coding Keys
- Windows Provider Detection
- Windows Usage & Gauge Metric
- Provider Card View (Mac)
- Dashboard View
- Refresh State & Codex Windows
- Windows App & Tray
- Claude Parser Tests
- Windows Claude Transcript Parser
- Window Router
- Formatting Helpers (Mac)
- Claude Provider (Mac)
- Status Aggregator Tests
- Current Window Parity Tests
- Incremental Parse Tests
- Windows Codex Rollout Parser
- Windows Refresh Scheduler
- Windows Threshold Alerts
- JSONL Reader (Mac)
- Session Blocks
- Windows Formatting Helpers
- Windows Events & Alerts
- Windows Stats & Scan Cache
- App Delegate (Lifecycle)
- Status Aggregator (Mac)
- Rhythm Chart View
- Codex Provider (Mac)
- Pricing Table (Mac)
- Format & Pricing Tests
- Precision Calibration Tests
- Windows Build Dependencies
- Notch Hit-Test View
- Windows JSONL Reader
- Windows App Paths & File Scan
- Windows Logger
- Windows Program Entry
- Windows Usage Store State
- Segmented Meter (Mac)
- Threshold Alerts Tests
- Windows Provider Interface
- Windows Pricing Table
- Appearance Application
- Gauge Metric (Mac)
- Pixel Mascot Glyph
- Windows Bar & Card Views
- Windows Tray Icon Factory
- Log (Mac)
- App Entry (SwiftUI Scene)
- SwiftPM Manifest
- App Packaging Script

## God Nodes (most connected - your core abstractions)
1. `Date` - 76 edges
2. `ProviderID` - 47 edges
3. `UsageStore` - 34 edges
4. `UsageStore` - 31 edges
5. `Foundation` - 29 edges
6. `NotchViewModel` - 27 edges
7. `SwiftUI` - 24 edges
8. `UsageSnapshot` - 24 edges
9. `SessionUsage` - 22 edges
10. `NotchAgent.Windows.Models` - 21 edges

## Surprising Connections (you probably didn't know these)
- `Shared JSONL Parsers / Calibrated Logic` --semantically_similar_to--> `UsageProvider Plugin Pattern`  [INFERRED] [semantically similar]
  windows/README.md → README.md
- `Floating Always-On-Top Bar` --semantically_similar_to--> `Notch Overlay (NSPanel hitTest)`  [INFERRED] [semantically similar]
  windows/README.md → README.md
- `StatusAggregatorTests` --calls--> `AppSettings`  [INFERRED]
  Tests/NotchAgentTests/AggregatorAndFormatTests.swift → Sources/NotchAgent/Core/Models/AppSettings.swift
- `NotchAgentApp` --implements--> `App`  [EXTRACTED]
  Sources/NotchAgent/App/NotchAgentApp.swift → windows/NotchAgent.Windows/App.axaml.cs
- `FloatingBarWindow` --inherits--> `Window`  [EXTRACTED]
  windows/NotchAgent.Windows/UI/FloatingBarWindow.axaml.cs → Sources/NotchAgent/Features/Providers/Codex/CodexRolloutParser.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Provider-to-UI Data Flow Pipeline** — readme_usage_provider_plugin, readme_usage_snapshot, readme_usage_store, readme_notch_overlay, readme_menu_bar, readme_dashboard [EXTRACTED 0.90]
- **Three Usage Providers** — readme_claude_provider, readme_codex_provider, readme_gemini_provider [EXTRACTED 0.90]
- **Pure Tested Computation Core** — readme_status_aggregator, readme_threshold_alerts, readme_burn_rate [EXTRACTED 0.85]
- **Multi-Provider Quota Monitoring** — docs_img_dashboard_1_claude_code_provider_card, docs_img_dashboard_2_codex_provider_card, docs_img_dashboard_2_gemini_cli_provider_card [INFERRED 0.85]
- **5h Session Limit Tracking** — docs_img_alert_almost_empty_alert_card, docs_img_desktop_burn_burn_projection_chart, docs_img_dashboard_1_claude_code_provider_card [INFERRED 0.75]
- **NotchAgent Popover Carousel Panels** — docs_img_desktop_now_expanded_status_panel, docs_img_panel_burn_burn_rate_projection, docs_img_panel_models_claude_models_panel [INFERRED 0.75]
- **NotchAgent Quota Visualizations** — docs_img_notch_compact_dot_quota_indicator, docs_img_desktop_now_segmented_quota_meter, docs_img_panel_burn_usage_projection_chart [INFERRED 0.75]
- **Swipeable Panel Set (NOW, RHYTHM)** — docs_img_panel_now_now_panel, docs_img_panel_rhythm_rhythm_panel, docs_img_panel_now_page_dots [INFERRED 0.75]

## Communities (91 total, 8 thin omitted)

### Community 0 - "Provider Protocol & Scheduler"
Cohesion: 0.07
Nodes (25): UsageProvider, RefreshScheduler, Bool, Never, SnapshotStore, Task, UsageStore, Void (+17 more)

### Community 1 - "Claude Transcript Parsing"
Cohesion: 0.09
Nodes (38): Decodable, ClaudeFileStat, ClaudeScanCache, ClaudeTranscriptParser, Entry, HourStat, Line, Message (+30 more)

### Community 2 - "Preferences & Snapshot Persistence"
Cohesion: 0.08
Nodes (18): JSONEncoder, PreferencesStore, AppSettings, SnapshotStore, JSONDecoder, URL, UsageSnapshot, BlockedCoherenceTests (+10 more)

### Community 3 - "Usage & Cost Models"
Cohesion: 0.16
Nodes (26): Codable, Equatable, CostEstimate, DailyTotal, HourlyTotal, ModelHealth, ModelProbeStatus, error (+18 more)

### Community 4 - "Burn Chart Rendering"
Cohesion: 0.12
Nodes (24): AnimatablePair, Path, Shape, BurnChartView, Bool, CGFloat, CGSize, Double (+16 more)

### Community 5 - "Docs & Design Rationale"
Cohesion: 0.07
Nodes (35): Retro Hardware Gauge Design System, Release 1.0.0, LSUIElement Agent App (No Dock), XcodeGen Spec (project.yml), anthropic-ratelimit-unified-* Headers, BurnRate Projection, Claude Code Provider, Claude Quota Probe (+27 more)

### Community 6 - "Claude Quota Probe (Mac)"
Cohesion: 0.11
Nodes (18): Security, ClaudeQuota, ClaudeQuotaProbe, ClaudeTokenLocator, Data, Double, Int, QuotaStatus (+10 more)

### Community 7 - "Settings & Attention Types"
Cohesion: 0.12
Nodes (19): AppSettings, AttentionLevel, Bool, Double, Int, Never, PercentSample, PreferencesStore (+11 more)

### Community 8 - "NOW Panel UI (Screenshots)"
Cohesion: 0.09
Nodes (29): NotchAgent NOW Panel Screenshot, Burn Rate and Runs-Out Projection, Claude Provider Card, Codex Provider Card, Gemini Not Installed Row, NOW Panel, Panel Page Dots Navigation, Panel Toolbar (Refresh, Pause, Dashboard, Settings) (+21 more)

### Community 9 - "Theme & Settings Enums"
Cohesion: 0.12
Nodes (24): CaseIterable, Comparable, Identifiable, Int, ThemeMode, auto, dark, light (+16 more)

### Community 10 - "Windows Runner Control"
Cohesion: 0.12
Nodes (16): Control, DateTime, Size, Typeface, Color, DateTimeOffset, DispatcherTimer, double (+8 more)

### Community 11 - "Burn Rate Projection"
Cohesion: 0.18
Nodes (11): BurnRate, PercentSample, Projection, Double, String, TimeInterval, Date, Timestamps (+3 more)

### Community 12 - "Menu Bar & Alert Views"
Cohesion: 0.09
Nodes (14): MenuBarLabelView, String, AlertMomentView, Color, Double, String, ThresholdAlert, Void (+6 more)

### Community 13 - "Notch View Model (Interaction)"
Cohesion: 0.16
Nodes (12): Edge, NSEvent, NotchViewModel, Bool, CGFloat, CGRect, CGSize, Int (+4 more)

### Community 14 - "Windows Theme & Brushes"
Cohesion: 0.18
Nodes (10): INotifyPropertyChanged, Color, IBrush, AppTheme, Color, DateTimeOffset, IBrush, BarViewModel (+2 more)

### Community 15 - "Mac Theme & Gauge Labels"
Cohesion: 0.18
Nodes (13): ColorScheme, Font, NSColor, GaugeLabel, StatusPill, Bool, CGFloat, Color (+5 more)

### Community 16 - "Preview Data & Notch Geometry"
Cohesion: 0.13
Nodes (9): NSScreen, PreviewData, Bool, NotchGeometry, Bool, CGFloat, CGRect, CGSize (+1 more)

### Community 17 - "App Environment & System Integration"
Cohesion: 0.16
Nodes (14): ServiceManagement, AppEnvironment, PreferencesStore, RefreshScheduler, SnapshotStore, UsageStore, BundleContext, LoginItem (+6 more)

### Community 18 - "Windows Settings & Fetch"
Cohesion: 0.15
Nodes (10): AppSettings, ThemeMode, AttentionLevel, CancellationToken, Task, PreferencesStore, Dictionary, IEnumerable (+2 more)

### Community 19 - "Compact Notch View"
Cohesion: 0.19
Nodes (11): Binding, NotchCompactView, Bool, Color, GaugeMetric, String, UsageSnapshot, SettingsView (+3 more)

### Community 20 - "Windows Usage Totals"
Cohesion: 0.14
Nodes (13): CostUsd, End, Start, Tokens, CancellationToken, DateTimeOffset, Dictionary, IEnumerable (+5 more)

### Community 21 - "Alert & Dashboard UI (Screenshots)"
Cohesion: 0.18
Nodes (18): Alert: Almost Empty (5h Window) Screenshot, Almost Empty Alert Card, Pixel Space-Invader Mascot, Segmented Quota Progress Bar, Dashboard (Top) Screenshot, Claude Code Provider Card, Hourly Rhythm Bar Chart, Range and Provider Filter Toggle (+10 more)

### Community 22 - "Windows Floating Bar Window"
Cohesion: 0.16
Nodes (7): PointerPressedEventArgs, Action, bool, CancellationTokenSource, DispatcherTimer, RoutedEventArgs, FloatingBarWindow

### Community 23 - "Windows Quota HTTP Probe"
Cohesion: 0.19
Nodes (10): HttpClient, IReadOnlyDictionary, bool, CancellationToken, DateTimeOffset, Task, TimeSpan, ClaudeQuota (+2 more)

### Community 24 - "Expanded Notch Panel Body"
Cohesion: 0.26
Nodes (8): ModelUsage, NotchExpandedView, Bool, Color, Double, Int, String, Void

### Community 25 - "Threshold Alerts & Restore Moment"
Cohesion: 0.26
Nodes (9): RestoreMoment, AttentionLevel, Bool, Double, Int, Set, String, ThresholdAlert (+1 more)

### Community 26 - "Codex & Gemini Parser Tests"
Cohesion: 0.14
Nodes (6): CodexParserTests, GeminiParserTests, URL, AppSettingsCompatibilityTests, ClaudeQuotaProbeParseTests, XCTestCase

### Community 27 - "Windows Usage Store"
Cohesion: 0.25
Nodes (5): CancellationTokenSource, Dictionary, int, List, UsageStore

### Community 28 - "App Bootstrap & Frameworks"
Cohesion: 0.16
Nodes (6): AppKit, Foundation, Observation, Mode, compact, expanded

### Community 29 - "Desktop Panel & Notch (Screenshots)"
Cohesion: 0.19
Nodes (16): Desktop NOW Panel Screenshot, Carousel Pagination Dots, Expanded Status Panel, Refresh Pause Dashboard Settings Controls, Segmented Quota Meter, Service Quota Card, Compact Notch Bar Screenshot, Compact Notch Bar (+8 more)

### Community 30 - "Provider Model & Capabilities"
Cohesion: 0.13
Nodes (14): Hashable, OptionSet, ProviderCapabilities, ProviderHealth, degraded, noData, notInstalled, ok (+6 more)

### Community 31 - "Windows Provider Model"
Cohesion: 0.17
Nodes (9): JsonSerializerOptions, ProviderHealth, ProviderHealthExtensions, ProviderId, ProviderIdExtensions, QuotaStatus, Dictionary, string (+1 more)

### Community 32 - "Notch Panel Window"
Cohesion: 0.23
Nodes (6): Any, NSPanel, NotchPanel, Bool, NotchWindowController, UsageStore

### Community 33 - "App Paths & File Stamp (Mac)"
Cohesion: 0.17
Nodes (11): ClaudeFileStat, AppPaths, FileStamp, recentFiles(), Int, String, URL, AppSettings (+3 more)

### Community 34 - "Windows Namespaces"
Cohesion: 0.27
Nodes (4): NotchAgent.Windows.UI, NotchAgent.Windows.Models, NotchAgent.Windows.Providers, NotchAgent.Windows.Services

### Community 35 - "Windows Provider Probes"
Cohesion: 0.17
Nodes (9): NotchAgent.Windows.Providers.Shared, NotchAgent.Windows.Providers.Codex, NotchAgent.Windows.Providers.Claude, ClaudeTokenLocator, double, int, Entry, HourStat (+1 more)

### Community 36 - "Settings Decoding & Integration Tests"
Cohesion: 0.18
Nodes (8): Decoder, AppSettings, Bool, Double, Int, ProviderIntegrationTests, String, URL

### Community 37 - "Windows Fullscreen Detection (P/Invoke)"
Cohesion: 0.25
Nodes (9): DllImport, IntPtr, MonitorInfo, Rect, uint, int, FullscreenDetector, MonitorInfo (+1 more)

### Community 38 - "Mac Test Suite Base"
Cohesion: 0.18
Nodes (5): NotchAgent, StaleWindowTests, URL, ModelBreakdownTests, XCTest

### Community 39 - "Windows Settings Window"
Cohesion: 0.22
Nodes (7): NumericUpDownValueChangedEventArgs, RangeBaseValueChangedEventArgs, SelectionChangedEventArgs, Action, bool, RoutedEventArgs, SettingsWindow

### Community 40 - "Menu Bar Content & Status"
Cohesion: 0.19
Nodes (11): MenuBarContentView, String, UsageSnapshot, AttentionDot, AttentionLevel, ProviderHealth, SparklineView, Color (+3 more)

### Community 41 - "Settings Coding Keys"
Cohesion: 0.14
Nodes (14): CodingKey, CodingKeys, claudeQuotaProbeEnabled, claudeSessionTokenBudget, claudeWeeklyTokenBudget, criticalThresholdPercent, fallbackPillEnabled, favoriteProvider (+6 more)

### Community 42 - "Windows Provider Detection"
Cohesion: 0.19
Nodes (10): IUsageProvider, Regex, CancellationToken, DateTimeOffset, Dictionary, ProviderInstallation, string, Task (+2 more)

### Community 43 - "Windows Usage & Gauge Metric"
Cohesion: 0.31
Nodes (12): long, DateTimeOffset, List, CostEstimate, DailyTotal, GaugeMetric, HourlyTotal, ModelUsage (+4 more)

### Community 44 - "Provider Card View (Mac)"
Cohesion: 0.25
Nodes (9): ProviderCardView, AttentionLevel, Color, GaugeMetric, Int, ProviderHealth, RefreshState, String (+1 more)

### Community 45 - "Dashboard View"
Cohesion: 0.31
Nodes (6): Charts, DashboardView, Int, String, UsageEvent, UsageSnapshot

### Community 46 - "Refresh State & Codex Windows"
Cohesion: 0.21
Nodes (11): Sendable, RefreshState, failure, idle, refreshing, success, CodexRateWindow, CodexTokenInfo (+3 more)

### Community 47 - "Windows App & Tray"
Cohesion: 0.24
Nodes (5): Application, IClassicDesktopStyleApplicationLifetime, NativeMenuItem, TrayIcon, App

### Community 48 - "Claude Parser Tests"
Cohesion: 0.18
Nodes (3): URL, ClaudeParserTests, URL

### Community 49 - "Windows Claude Transcript Parser"
Cohesion: 0.24
Nodes (7): byte, Consumed, ReadOnlySpan, Stat, DateTimeOffset, JsonElement, ClaudeTranscriptParser

### Community 50 - "Window Router"
Cohesion: 0.36
Nodes (6): NSRect, NSSize, NSWindow, AnyView, String, WindowRouter

### Community 51 - "Formatting Helpers (Mac)"
Cohesion: 0.40
Nodes (4): Format, Double, Int, String

### Community 52 - "Claude Provider (Mac)"
Cohesion: 0.22
Nodes (7): ClaudeProvider, ClaudeQuota, ClaudeQuotaProbe, ProviderInstallation, String, TimeInterval, URL

### Community 53 - "Status Aggregator Tests"
Cohesion: 0.29
Nodes (4): StatusAggregatorTests, Double, ProviderHealth, UsageSnapshot

### Community 54 - "Current Window Parity Tests"
Cohesion: 0.18
Nodes (3): CurrentWindowParityTests, URL, UUID

### Community 55 - "Incremental Parse Tests"
Cohesion: 0.29
Nodes (4): IncrementalParseTests, Int, String, URL

### Community 56 - "Windows Codex Rollout Parser"
Cohesion: 0.35
Nodes (5): DateTimeOffset, JsonElement, CodexRateWindow, CodexRolloutParser, CodexTokenInfo

### Community 57 - "Windows Refresh Scheduler"
Cohesion: 0.25
Nodes (6): bool, CancellationToken, CancellationTokenSource, List, Task, RefreshScheduler

### Community 58 - "Windows Threshold Alerts"
Cohesion: 0.20
Nodes (6): AttentionLevel, double, HashSet, int, ThresholdAlert, ThresholdAlerts

### Community 59 - "JSONL Reader (Mac)"
Cohesion: 0.27
Nodes (7): JSONLReader, Bool, Data, Int, UInt64, URL, Void

### Community 60 - "Session Blocks"
Cohesion: 0.33
Nodes (4): SessionBlocks, TimeInterval, SessionBlockTests, Double

### Community 62 - "Windows Events & Alerts"
Cohesion: 0.31
Nodes (8): EventKind, Guid, DateTimeOffset, EventKind, ProviderAlert, RestoreMoment, ThresholdAlert, UsageEvent

### Community 63 - "Windows Stats & Scan Cache"
Cohesion: 0.28
Nodes (7): HourStat, ModelStat, object, Dictionary, HashSet, ClaudeFileStat, ClaudeScanCache

### Community 64 - "App Delegate (Lifecycle)"
Cohesion: 0.22
Nodes (6): Notification, NSApplication, NSApplicationDelegate, NSObject, AppDelegate, Bool

### Community 65 - "Status Aggregator (Mac)"
Cohesion: 0.47
Nodes (5): StatusAggregator, AppSettings, AttentionLevel, ProviderAlert, UsageSnapshot

### Community 66 - "Rhythm Chart View"
Cohesion: 0.33
Nodes (6): PagerDots, RhythmChartView, CGSize, Color, Double, Int

### Community 67 - "Codex Provider (Mac)"
Cohesion: 0.28
Nodes (4): CodexProvider, ProviderInstallation, TimeInterval, URL

### Community 68 - "Pricing Table (Mac)"
Cohesion: 0.42
Nodes (5): ModelPricing, PricingTable, Double, String, TokenUsage

### Community 70 - "Precision Calibration Tests"
Cohesion: 0.31
Nodes (4): PrecisionCalibrationTests, Int, String, URL

### Community 71 - "Windows Build Dependencies"
Cohesion: 0.25
Nodes (7): net8.0, Avalonia (11.2.5), Avalonia.Desktop (11.2.5), Avalonia.Diagnostics (11.2.5), Avalonia.Fonts.Inter (11.2.5), Avalonia.Themes.Fluent (11.2.5), Microsoft.NET.Sdk

### Community 72 - "Notch Hit-Test View"
Cohesion: 0.25
Nodes (6): NSHostingView, NSPoint, NSView, NotchHitTestView, AnyView, CGRect

### Community 73 - "Windows JSONL Reader"
Cohesion: 0.29
Nodes (4): ReadOnlyMemory, Action, List, JsonlReader

### Community 74 - "Windows App Paths & File Scan"
Cohesion: 0.25
Nodes (5): DateTimeOffset, List, AppPaths, FileScan, FileStamp

### Community 75 - "Windows Logger"
Cohesion: 0.39
Nodes (3): string, Log, Logger

### Community 76 - "Windows Program Entry"
Cohesion: 0.33
Nodes (4): AppBuilder, NotchAgent.Windows, STAThread, Program

### Community 77 - "Windows Usage Store State"
Cohesion: 0.52
Nodes (6): Failure, Idle, PercentSample, Refreshing, RefreshState, Success

### Community 78 - "Segmented Meter (Mac)"
Cohesion: 0.33
Nodes (5): SegmentedMeter, CGFloat, Color, Double, Int

### Community 80 - "Windows Provider Interface"
Cohesion: 0.40
Nodes (3): IUsageProvider, ProviderInstallation, ProviderInstallationKind

### Community 81 - "Windows Pricing Table"
Cohesion: 0.47
Nodes (3): string, ModelPricing, PricingTable

### Community 83 - "Gauge Metric (Mac)"
Cohesion: 0.50
Nodes (3): GaugeMetric, Bool, UsageSnapshot

### Community 84 - "Pixel Mascot Glyph"
Cohesion: 0.40
Nodes (4): PixelGlyph, Color, Double, Int

### Community 85 - "Windows Bar & Card Views"
Cohesion: 0.40
Nodes (3): UserControl, CompactBarView, ProviderCardView

### Community 86 - "Windows Tray Icon Factory"
Cohesion: 0.40
Nodes (3): WindowIcon, Color, TrayIconFactory

## Knowledge Gaps
- **89 isolated node(s):** `PackageDescription`, `make-app.sh script`, `os`, `Log`, `auto` (+84 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **8 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Window` connect `Claude Transcript Parsing` to `Windows Floating Bar Window`, `Windows Settings Window`?**
  _High betweenness centrality (0.234) - this node is a cross-community bridge._
- **Why does `Date` connect `Burn Rate Projection` to `Provider Protocol & Scheduler`, `Claude Transcript Parsing`, `Preferences & Snapshot Persistence`, `Usage & Cost Models`, `Burn Chart Rendering`, `Claude Quota Probe (Mac)`, `Theme & Settings Enums`, `Notch View Model (Interaction)`, `Threshold Alerts & Restore Moment`, `App Paths & File Stamp (Mac)`, `Settings Decoding & Integration Tests`, `Mac Test Suite Base`, `Provider Card View (Mac)`, `Refresh State & Codex Windows`, `Claude Parser Tests`, `Formatting Helpers (Mac)`, `Current Window Parity Tests`, `Session Blocks`, `Codex Provider (Mac)`, `Format & Pricing Tests`, `Precision Calibration Tests`?**
  _High betweenness centrality (0.180) - this node is a cross-community bridge._
- **Why does `SettingsWindow` connect `Windows Settings Window` to `Claude Transcript Parsing`, `Windows Namespaces`, `Windows Settings & Fetch`, `Windows App & Tray`?**
  _High betweenness centrality (0.125) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `Date` (e.g. with `.handleScroll()` and `.fetchSnapshot()`) actually correct?**
  _`Date` has 16 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `make-app.sh script`, `os` to the rest of the system?**
  _93 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Provider Protocol & Scheduler` be split into smaller, more focused modules?**
  _Cohesion score 0.06972789115646258 - nodes in this community are weakly interconnected._
- **Should `Claude Transcript Parsing` be split into smaller, more focused modules?**
  _Cohesion score 0.08603145235892692 - nodes in this community are weakly interconnected._