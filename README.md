# Typist

Typist is an ultra-light macOS menu bar app (macOS 14+) that tracks:
- Total keystrokes
- Word counts (privacy-safe boundary heuristic)
- Per-key frequency
- Built-in vs external keyboard usage (best-effort, with unknown fallback)
- Interactive keyboard heatmap (Mac ANSI layout) with per-key drilldown

It stores only local aggregate metrics and never stores typed text.

## Run

```bash
swift run TypistMenuBar
```

On first run, grant **Input Monitoring** in System Settings when prompted.
If no prompt appears, use the in-app **Open Settings** button and enable Typist manually under:
`System Settings > Privacy & Security > Input Monitoring`.

## Test

```bash
swift test
```

## Architecture

- `Sources/TypistCore`
- `MetricsEngine`: low-overhead ingest, batching, and flush orchestration.
- `SQLiteStore`: WAL-mode SQLite persistence with hourly/daily aggregates and 90-day ring buffer retention.
- `WordCounterStateMachine`: separator-boundary counting with no text capture.

- `Sources/TypistMenuBar`
- `HIDKeyboardCaptureService`: HID input capture.
- `MenuBarController`: NSStatusItem + popover lifecycle.
- `AppModel`: permission flow, refresh loops, and UI state.
- `Views/*`: BatFi-inspired translucent popover, tabbed settings, and keyboard heatmap UI.

## Privacy defaults

- No typed content captured or stored.
- Only key usage metadata is persisted locally.
- 90-day event ring buffer with long-term aggregate tables.

## Performance and battery validation

Use these checks before release:

1. **Functional correctness**
   - Verify key counts and words across timeframes (`1H`, `12H`, `24H`, `7D`, `30D`, `All`).
   - Verify built-in/external split using internal and USB/Bluetooth keyboards.
   - Verify permission denied/regranted behavior.

2. **Instruments Energy Log**
   - Scenario A: app idle with popover closed for 30 min.
   - Scenario B: sustained typing for 5 min.
   - Target: near-zero CPU while idle and minimal wakeups.

3. **Instruments Time Profiler**
   - Ensure callbacks, aggregation, and flush remain lightweight during burst typing.

4. **Storage checks**
   - Confirm DB growth remains bounded and ring-buffer pruning executes hourly.

## Debugging instrumentation

If counters stop updating, open the popover and check the **Diagnostics** section:
- `hid` and `yielded` should increase while typing.
- `app` and `engIn` should track close to `yielded`.
- `pending` should increase briefly and then flush.

Use **Copy Debug** to copy a full diagnostics report (pipeline counters + recent log lines) to your clipboard.

## Packaging (direct-download path)

1. Open package in Xcode.
2. Archive with a Developer ID signing identity.
3. Notarize and staple the app bundle.
