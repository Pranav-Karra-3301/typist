# Repository Guidelines

## Project Structure & Module Organization
`Typist` is a Swift Package with two main targets:
- `Sources/TypistCore`: core domain and persistence logic (`MetricsEngine`, `SQLiteStore`, models, key mapping).
- `Sources/TypistMenuBar`: macOS app entrypoint, app state, services, and SwiftUI/AppKit UI (`Views/`, `Services/`).
- `Tests/TypistCoreTests`: XCTest coverage for core behavior (metrics aggregation, persistence, timeframes, diagnostics).
- `Package.swift`: package definition, platform minimum (`macOS 14`), target dependencies, linked frameworks.

Keep new code in the target that owns it: reusable logic in `TypistCore`, UI/system integration in `TypistMenuBar`.

## Build, Test, and Development Commands
- `swift run TypistMenuBar`: run the menu bar app locally.
- `swift build`: compile all targets without running.
- `swift test`: run the full test suite.
- `swift test --filter MetricsEngineTests`: run a focused test class during iteration.

Use `swift test` before opening a PR.

## Coding Style & Naming Conventions
- Follow Swift defaults: 4-space indentation, no tabs, and clear access control (`public` only when needed).
- Types/protocols: `UpperCamelCase` (`KeyboardCaptureProviding`).
- Properties/functions/enums cases: `lowerCamelCase` (`selectedTimeframe`, `startCapture()`).
- Test methods should describe behavior and start with `test...` (for example, `testFlushTriggeredAtThreshold`).
- Prefer small, focused files grouped by feature area (`Views`, `Services`, core engine/persistence).

## Testing Guidelines
- Framework: `XCTest` under `Tests/TypistCoreTests`.
- Add or update tests for every `TypistCore` behavior change, especially around aggregation, time windows, and SQLite persistence.
- Keep tests deterministic (fixed timestamps, controlled input events) and isolated (temporary DB paths).
- There is no enforced coverage threshold; maintain or improve existing coverage for touched areas.

## Commit & Pull Request Guidelines
- Use Conventional Commit style seen in history: `feat: ...`, `feat(ui): ...`, `fix: ...`, `test: ...`, `docs: ...`.
- Keep commits scoped to one change and message the user impact.
- PRs should include:
  - concise summary of behavior changes,
  - test evidence (`swift test` output),
  - screenshots/video for UI changes in `TypistMenuBar`,
  - notes on permission/privacy-impacting changes (Input Monitoring, data handling).

## Security & Privacy Notes
- Never add typed text capture/storage. Persist only aggregate metrics.
- Treat Input Monitoring flows as sensitive UX; preserve explicit permission prompts and fallback guidance.
