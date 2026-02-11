# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
swift run TypistMenuBar    # Run the menu bar app
swift test                 # Run all tests
swift build                # Build without running
swift test --filter TypistCoreTests.SQLiteStoreTests  # Run a single test class
```

Requires macOS 14+. Swift Package Manager is the build system (Package.swift). No external dependencies — only Apple system frameworks and sqlite3.

## Architecture

Two targets with a clean separation:

**TypistCore** (library) — Pure business logic, fully testable without UI or HID access:
- `MetricsEngine` (actor): Ingests `KeyEvent` streams, batches in memory (flush at 200 events or 5s interval), merges pending + persisted data for snapshots
- `SQLiteStore`: WAL-mode SQLite on a serial DispatchQueue. Hourly/daily aggregate tables with 90-day ring-buffer pruning. DB at `~/Library/Application Support/Typist/typist.sqlite3`
- `WordCounterStateMachine` (struct, Sendable): Emits word increments only at separator boundaries — no text capture
- `Models.swift`: `KeyEvent`, `StatsSnapshot`, `Timeframe` enum, `DeviceClass`, and the `TypistStore` protocol (composite of `PersistenceWriting`, `StatsQuerying`, `StatsResetting`)

**TypistMenuBar** (executable) — macOS menu bar app:
- `AppDelegate`: Wires database, engine, capture service, and UI at launch
- `AppModel` (@MainActor): Central state holder — coordinates permissions, HID capture, stats refresh, and publishes to UI
- `HIDKeyboardCaptureService`: IOKit HID capture yielding `AsyncStream<KeyEvent>`; uses `DeviceClassifier` for built-in/external detection
- `MenuBarController`: NSStatusItem + NSPopover lifecycle with click-to-toggle and outside-click dismiss
- Views: SwiftUI popover (`MenuPopoverView`), keyboard heatmap (`KeyboardHeatmapView`), trend chart (`TrendChartView` using Charts framework), settings window (`SettingsView`, 3 tabs)

**Data flow**: `HIDKeyboardCaptureService` → `AsyncStream<KeyEvent>` → `MetricsEngine` (batch + flush) → `SQLiteStore` → `AppModel` (snapshot queries) → SwiftUI views

## Concurrency Model

- `MetricsEngine` is a Swift actor — all ingestion and flush logic is actor-isolated
- `SQLiteStore` uses a serial `DispatchQueue` (utility QoS) with `@unchecked Sendable`
- `AppModel` is `@MainActor` — UI state coordination
- `AppDiagnostics` is a singleton with `NSLock` for thread-safe counters
- Tests use `MockStore` (actor conforming to `TypistStore`)

## Testing

Tests cover only `TypistCore` (no UI tests). Key patterns:
- `MockStore` actor stands in for `SQLiteStore` in engine tests
- `SQLiteStoreTests` use temporary file URLs for database isolation
- All test methods are async
- `MetricsEngineTests` verify snapshot correctness, flush thresholds, and batch merging

## Privacy Constraint

The app never captures or stores typed text. Only aggregate metadata (key counts, device class, timestamps) is persisted. Any code changes must preserve this invariant.
