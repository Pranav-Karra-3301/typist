import AppKit
import Foundation
import IOKit.hid
import TypistCore

enum HIDKeyboardCaptureError: Error {
    case managerOpenFailed(code: IOReturn)
}

final class HIDKeyboardCaptureService: KeyboardCaptureProviding {
    var events: AsyncStream<KeyEvent> { stream }

    private let stream: AsyncStream<KeyEvent>
    private let continuation: AsyncStream<KeyEvent>.Continuation

    private let deviceClassifier = DeviceClassifier()
    private let diagnostics = AppDiagnostics.shared
    private var manager: IOHIDManager?
    private var cachedProcessID: pid_t?
    private var cachedAppBundleID: String?
    private var cachedAppName: String?
    private let runLoopMode = CFRunLoopMode.commonModes.rawValue

    init() {
        var localContinuation: AsyncStream<KeyEvent>.Continuation!
        stream = AsyncStream<KeyEvent> { continuation in
            localContinuation = continuation
        }
        continuation = localContinuation
    }

    func start() throws {
        guard manager == nil else { return }
        diagnostics.mark("Starting HID capture service")

        let newManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = newManager

        let matchers: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_Keyboard)
            ],
            [
                kIOHIDDeviceUsagePageKey as String: Int(kHIDPage_GenericDesktop),
                kIOHIDDeviceUsageKey as String: Int(kHIDUsage_GD_Keypad)
            ]
        ]

        IOHIDManagerSetDeviceMatchingMultiple(newManager, matchers as CFArray)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterInputValueCallback(newManager, hidInputCallback, context)
        IOHIDManagerScheduleWithRunLoop(newManager, CFRunLoopGetMain(), runLoopMode)

        let result = IOHIDManagerOpen(newManager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            manager = nil
            diagnostics.mark("HID manager open failed with code \(result)")
            throw HIDKeyboardCaptureError.managerOpenFailed(code: result)
        }
        diagnostics.mark("HID manager opened successfully")
    }

    func stop() {
        guard let manager else { return }

        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), runLoopMode)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
        diagnostics.mark("HID capture service stopped")
    }

    fileprivate func handle(value: IOHIDValue) {
        diagnostics.recordHIDCallback()

        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)

        // 0x07 is the HID usage page for keyboard/keypad keys.
        guard usagePage == 0x07 else {
            diagnostics.recordHIDNonKeyboardDrop()
            return
        }

        let rawValue = IOHIDValueGetIntegerValue(value)
        guard rawValue != 0 else {
            diagnostics.recordHIDKeyUpDrop()
            return
        }

        let keyCode = Int(IOHIDElementGetUsage(element))
        guard KeyboardKeyMapper.isTrackableKeyCode(keyCode) else {
            diagnostics.recordHIDInvalidKeyDrop(keyCode: keyCode)
            return
        }

        let device = IOHIDElementGetDevice(element)
        let deviceClass = deviceClassifier.classify(device: device)
        let frontmostApp = currentFrontmostApp()

        let event = KeyEvent(
            timestamp: Date(),
            keyCode: keyCode,
            isSeparator: KeyboardKeyMapper.isSeparator(keyCode),
            deviceClass: deviceClass,
            appBundleID: frontmostApp.bundleID,
            appName: frontmostApp.name
        )

        diagnostics.recordHIDYieldedEvent(event)
        continuation.yield(event)
    }

    private func currentFrontmostApp() -> (bundleID: String?, name: String?) {
        guard let appInfo = FrontmostAppResolver.current() else {
            cachedProcessID = nil
            cachedAppBundleID = nil
            cachedAppName = nil
            return (bundleID: nil, name: nil)
        }

        if cachedProcessID == appInfo.processID {
            return (bundleID: cachedAppBundleID, name: cachedAppName)
        }

        cachedProcessID = appInfo.processID
        cachedAppBundleID = appInfo.bundleID
        cachedAppName = appInfo.name
        return (bundleID: cachedAppBundleID, name: cachedAppName)
    }
}

private let hidInputCallback: IOHIDValueCallback = { context, _, _, value in
    guard let context else {
        return
    }

    let service = Unmanaged<HIDKeyboardCaptureService>.fromOpaque(context).takeUnretainedValue()
    service.handle(value: value)
}
