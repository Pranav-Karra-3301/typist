import Foundation
import os
import TypistCore

struct AppDiagnosticsSnapshot {
    let permissionChecks: Int
    let permissionRequests: Int
    let permissionGrantedChecks: Int
    let captureStartAttempts: Int
    let captureStartSuccesses: Int
    let captureStartFailures: Int
    let hidCallbacks: Int
    let hidNonKeyboardDrops: Int
    let hidKeyUpDrops: Int
    let hidInvalidKeyDrops: Int
    let hidYieldedEvents: Int
    let appReceivedEvents: Int
    let resets: Int
    let lines: [String]
}

final class AppDiagnostics {
    static let shared = AppDiagnostics()
    private static let timestampFormatter = ISO8601DateFormatter()

    private let logger = Logger(subsystem: "com.typist.app", category: "diagnostics")
    private let lock = NSLock()

    private let maxLines = 120
    private var lines: [String] = []

    private var permissionChecks = 0
    private var permissionRequests = 0
    private var permissionGrantedChecks = 0
    private var captureStartAttempts = 0
    private var captureStartSuccesses = 0
    private var captureStartFailures = 0
    private var hidCallbacks = 0
    private var hidNonKeyboardDrops = 0
    private var hidKeyUpDrops = 0
    private var hidInvalidKeyDrops = 0
    private var hidYieldedEvents = 0
    private var appReceivedEvents = 0
    private var resets = 0

    private init() {}

    func mark(_ message: String) {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"

        lock.lock()
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        lock.unlock()

        logger.info("\(message, privacy: .public)")
    }

    func recordPermissionCheck(granted: Bool) {
        lock.lock()
        permissionChecks += 1
        if granted {
            permissionGrantedChecks += 1
        }
        lock.unlock()
    }

    func recordPermissionRequest(granted: Bool) {
        lock.lock()
        permissionRequests += 1
        lock.unlock()
        mark("Permission request result: \(granted ? "granted" : "not granted")")
    }

    func recordCaptureStartAttempt() {
        lock.lock()
        captureStartAttempts += 1
        lock.unlock()
    }

    func recordCaptureStartSuccess() {
        lock.lock()
        captureStartSuccesses += 1
        lock.unlock()
        mark("Capture service started")
    }

    func recordCaptureStartFailure(_ error: Error) {
        lock.lock()
        captureStartFailures += 1
        lock.unlock()
        mark("Capture start failed: \(error.localizedDescription)")
    }

    func recordHIDCallback() {
        lock.lock()
        hidCallbacks += 1
        lock.unlock()
    }

    func recordHIDNonKeyboardDrop() {
        lock.lock()
        hidNonKeyboardDrops += 1
        lock.unlock()
    }

    func recordHIDKeyUpDrop() {
        lock.lock()
        hidKeyUpDrops += 1
        lock.unlock()
    }

    func recordHIDInvalidKeyDrop(keyCode: Int) {
        lock.lock()
        hidInvalidKeyDrops += 1
        let shouldLog = hidInvalidKeyDrops <= 5 || hidInvalidKeyDrops % 250 == 0
        lock.unlock()

        if shouldLog {
            mark("Dropped invalid key usage: \(keyCode)")
        }
    }

    func recordHIDYieldedEvent(_ event: KeyEvent) {
        lock.lock()
        hidYieldedEvents += 1
        let shouldLog = hidYieldedEvents <= 5 || hidYieldedEvents % 250 == 0
        lock.unlock()

        if shouldLog {
            mark("Yielded key event: keyCode=\(event.keyCode) device=\(event.deviceClass.rawValue)")
        }
    }

    func recordAppReceivedEvent(_ event: KeyEvent) {
        lock.lock()
        appReceivedEvents += 1
        let shouldLog = appReceivedEvents <= 5 || appReceivedEvents % 250 == 0
        lock.unlock()

        if shouldLog {
            mark("App received key event: keyCode=\(event.keyCode) device=\(event.deviceClass.rawValue)")
        }
    }

    func recordReset() {
        lock.lock()
        resets += 1
        lock.unlock()
        mark("Reset stats triggered")
    }

    func snapshot() -> AppDiagnosticsSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return AppDiagnosticsSnapshot(
            permissionChecks: permissionChecks,
            permissionRequests: permissionRequests,
            permissionGrantedChecks: permissionGrantedChecks,
            captureStartAttempts: captureStartAttempts,
            captureStartSuccesses: captureStartSuccesses,
            captureStartFailures: captureStartFailures,
            hidCallbacks: hidCallbacks,
            hidNonKeyboardDrops: hidNonKeyboardDrops,
            hidKeyUpDrops: hidKeyUpDrops,
            hidInvalidKeyDrops: hidInvalidKeyDrops,
            hidYieldedEvents: hidYieldedEvents,
            appReceivedEvents: appReceivedEvents,
            resets: resets,
            lines: lines
        )
    }
}
