import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private unowned let appModel: AppModel
    private var globalClickMonitor: Any?
    private var localClickMonitor: Any?
    private var currentStatusState = StatusItemState(text: "--", iconStyle: .dynamic, monochrome: true)

    init(appModel: AppModel) {
        self.appModel = appModel
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()
        configureStatusItem()
        configurePopover()
    }

    func applyStatusItemState(_ state: StatusItemState) {
        currentStatusState = state

        guard let button = statusItem.button else { return }

        button.image = makeStatusIcon(style: state.iconStyle)
        button.imagePosition = .imageLeading
        button.contentTintColor = state.monochrome ? nil : NSColor.systemMint

        if state.text.isEmpty {
            button.title = button.image == nil ? "❀" : ""
        } else if button.image != nil {
            button.title = " \(state.text)"
        } else {
            button.title = "❀ \(state.text)"
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
            appModel.setPopoverVisible(false)
            stopDismissMonitoring()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            appModel.setPopoverVisible(true)
            startDismissMonitoring()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        appModel.setPopoverVisible(false)
        stopDismissMonitoring()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        applyStatusItemState(currentStatusState)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 344, height: 690)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuPopoverView(appModel: appModel))
    }

    private func startDismissMonitoring() {
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.dismissPopoverIfNeeded()
                }
            }
        }

        if localClickMonitor == nil {
            localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
                guard let self else { return event }
                guard self.popover.isShown else { return event }

                let popoverWindow = self.popover.contentViewController?.view.window
                let statusWindow = self.statusItem.button?.window
                if event.window === popoverWindow || event.window === statusWindow {
                    return event
                }

                self.dismissPopoverIfNeeded()
                return event
            }
        }
    }

    private func stopDismissMonitoring() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
    }

    private func dismissPopoverIfNeeded() {
        guard popover.isShown else { return }
        popover.performClose(nil)
        appModel.setPopoverVisible(false)
        stopDismissMonitoring()
    }

    private func makeStatusIcon(style: StatusIconStyle) -> NSImage? {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else {
            return nil
        }

        let iconRect = CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5)
        context.saveGState()
        context.translateBy(x: iconRect.minX, y: iconRect.minY)
        context.scaleBy(x: iconRect.width / 24.0, y: iconRect.height / 24.0)
        context.setShouldAntialias(true)

        switch style {
        case .dynamic:
            guard let path = StatusRosetteIcon.outlinePath else {
                context.restoreGState()
                return fallbackIcon()
            }
            context.addPath(path)
            context.setLineWidth(1.5)
            context.setStrokeColor(NSColor.black.cgColor)
            context.strokePath()

        case .minimal:
            guard let path = StatusRosetteIcon.outlinePath else {
                context.restoreGState()
                return fallbackIcon()
            }
            context.translateBy(x: 12, y: 12)
            context.scaleBy(x: 0.9, y: 0.9)
            context.translateBy(x: -12, y: -12)
            context.addPath(path)
            context.setLineWidth(1.25)
            context.setStrokeColor(NSColor.black.cgColor)
            context.strokePath()

        case .glyph:
            guard let path = StatusRosetteIcon.solidPath else {
                context.restoreGState()
                return fallbackIcon()
            }
            context.addPath(path)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
        }

        context.restoreGState()
        image.isTemplate = true
        return image
    }

    private func fallbackIcon() -> NSImage? {
        if let image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Typist") {
            image.isTemplate = true
            return image
        }
        return nil
    }
}

private enum StatusRosetteIcon {
    static let outlinePathData =
        "M12 2.25C12.8779 2.25 13.6647 3.53925 14.2007 5.58056C14.2893 5.91782 14.6811 6.08013 14.9822 5.90427C16.805 4.83972 18.2738 4.48465 18.8946 5.10544C19.5153 5.72622 19.1594 7.19426 18.0948 9.01675C17.9189 9.31784 18.0812 9.70971 18.4185 9.79827C20.4604 10.3344 21.75 11.122 21.75 12C21.75 12.878 20.4603 13.6648 18.4185 14.2007C18.0812 14.2893 17.9189 14.6812 18.0948 14.9823C19.1597 16.8051 19.5154 18.2737 18.8946 18.8946C18.2737 19.5154 16.8051 19.1597 14.9823 18.0948C14.6812 17.9189 14.2893 18.0812 14.2007 18.4185C13.6648 20.4603 12.878 21.75 12 21.75C11.122 21.75 10.3344 20.4604 9.79827 18.4185C9.70971 18.0812 9.31784 17.9189 9.01675 18.0948C7.19425 19.1594 5.72622 19.5153 5.10544 18.8946C4.48464 18.2738 4.8397 16.805 5.90427 14.9822C6.08013 14.6811 5.91782 14.2893 5.58056 14.2007C3.53925 13.6647 2.25 12.8779 2.25 12C2.25 11.1221 3.53918 10.3345 5.58059 9.7983C5.91784 9.70972 6.08015 9.31788 5.9043 9.01678C4.84 7.1944 4.48473 5.72616 5.10544 5.10544C5.72617 4.48475 7.19441 4.84001 9.01678 5.9043C9.31788 6.08015 9.70972 5.91784 9.7983 5.58059C10.3345 3.53918 11.1221 2.25 12 2.25Z"

    static let solidPathData =
        "M12 1.5C12.8323 1.5 13.4447 2.10247 13.8584 2.74219C14.2544 3.35461 14.5835 4.17321 14.8496 5.11621C15.7051 4.63723 16.5179 4.29273 17.2314 4.13965C17.9766 3.97986 18.8362 3.98662 19.4248 4.5752C20.0134 5.16378 20.0203 6.02282 19.8604 6.76758C19.7071 7.4809 19.3608 8.29315 18.8818 9.14844C19.8257 9.41472 20.645 9.74516 21.2578 10.1416C21.8976 10.5556 22.5 11.1679 22.5 12L22.4932 12.1533C22.4247 12.9082 21.8568 13.4705 21.2568 13.8584C20.6441 14.2545 19.8254 14.5835 18.8818 14.8496C19.3611 15.7053 19.7071 16.5178 19.8604 17.2314C20.0203 17.9765 20.0135 18.8361 19.4248 19.4248C18.8361 20.0135 17.9765 20.0203 17.2314 19.8604C16.5178 19.7071 15.7053 19.3611 14.8496 18.8818C14.5835 19.8254 14.2545 20.6441 13.8584 21.2568C13.4447 21.8968 12.8325 22.5 12 22.5C11.1679 22.5 10.5556 21.8976 10.1416 21.2578C9.74516 20.645 9.41472 19.8257 9.14844 18.8818C8.29314 19.3608 7.4809 19.7071 6.76758 19.8604C6.02281 20.0203 5.16378 20.0134 4.5752 19.4248C3.98662 18.8362 3.97986 17.9766 4.13965 17.2314C4.29273 16.5179 4.63722 15.7051 5.11621 14.8496C4.1732 14.5835 3.35461 14.2544 2.74219 13.8584C2.14241 13.4705 1.57531 12.9079 1.50684 12.1533L1.5 12C1.5 11.1679 2.10247 10.5556 2.74219 10.1416C3.35469 9.74527 4.17296 9.4147 5.11621 9.14844C4.63748 8.29327 4.29267 7.48085 4.13965 6.76758C3.97988 6.02268 3.98669 5.1637 4.5752 4.5752C5.1637 3.98672 6.02268 3.97988 6.76758 4.13965C7.48085 4.29267 8.29327 4.63748 9.14844 5.11621C9.4147 4.17296 9.74527 3.35469 10.1416 2.74219C10.5556 2.10247 11.1679 1.5 12 1.5Z"

    static let outlinePath: CGPath? = {
        var parser = SVGPathParser(outlinePathData)
        return parser.parse()
    }()

    static let solidPath: CGPath? = {
        var parser = SVGPathParser(solidPathData)
        return parser.parse()
    }()
}

private struct SVGPathParser {
    private let scalars: [UnicodeScalar]
    private var index = 0
    private var currentCommand: UnicodeScalar?

    init(_ pathData: String) {
        scalars = Array(pathData.unicodeScalars)
    }

    mutating func parse() -> CGPath? {
        let path = CGMutablePath()

        while true {
            skipSeparators()
            guard index < scalars.count else { break }

            if isCommand(scalars[index]) {
                currentCommand = scalars[index]
                index += 1
            } else if currentCommand == nil {
                return nil
            }

            guard let command = currentCommand else { return nil }

            switch command {
            case "M":
                guard let start = readPoint() else { return nil }
                path.move(to: start)
                currentCommand = "L"
                while let point = readPointIfPresent() {
                    path.addLine(to: point)
                }
            case "L":
                guard let first = readPoint() else { return nil }
                path.addLine(to: first)
                while let point = readPointIfPresent() {
                    path.addLine(to: point)
                }
            case "C":
                guard let c1 = readPoint(), let c2 = readPoint(), let end = readPoint() else { return nil }
                path.addCurve(to: end, control1: c1, control2: c2)
                while true {
                    let checkpoint = index
                    guard let nextC1 = readPoint(), let nextC2 = readPoint(), let nextEnd = readPoint() else {
                        index = checkpoint
                        break
                    }
                    path.addCurve(to: nextEnd, control1: nextC1, control2: nextC2)
                }
            case "Z":
                path.closeSubpath()
                currentCommand = nil
            default:
                return nil
            }
        }

        return path
    }

    private mutating func readPoint() -> CGPoint? {
        guard let x = readNumber(), let y = readNumber() else { return nil }
        return CGPoint(x: x, y: y)
    }

    private mutating func readPointIfPresent() -> CGPoint? {
        let checkpoint = index
        guard let point = readPoint() else {
            index = checkpoint
            return nil
        }
        return point
    }

    private mutating func readNumber() -> CGFloat? {
        skipSeparators()
        guard index < scalars.count else { return nil }

        let start = index

        if scalars[index] == "+" || scalars[index] == "-" {
            index += 1
        }

        var sawDigit = false
        while index < scalars.count, isDigit(scalars[index]) {
            sawDigit = true
            index += 1
        }

        if index < scalars.count, scalars[index] == "." {
            index += 1
            while index < scalars.count, isDigit(scalars[index]) {
                sawDigit = true
                index += 1
            }
        }

        guard sawDigit else {
            index = start
            return nil
        }

        if index < scalars.count, scalars[index] == "e" || scalars[index] == "E" {
            let expStart = index
            index += 1
            if index < scalars.count, scalars[index] == "+" || scalars[index] == "-" {
                index += 1
            }
            var expDigits = false
            while index < scalars.count, isDigit(scalars[index]) {
                expDigits = true
                index += 1
            }
            if !expDigits {
                index = expStart
            }
        }

        let numberString = String(String.UnicodeScalarView(scalars[start..<index]))
        guard let value = Double(numberString) else {
            index = start
            return nil
        }
        return CGFloat(value)
    }

    private mutating func skipSeparators() {
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == " " || scalar == "," || scalar == "\n" || scalar == "\t" || scalar == "\r" {
                index += 1
            } else {
                break
            }
        }
    }

    private func isCommand(_ scalar: UnicodeScalar) -> Bool {
        scalar == "M" || scalar == "L" || scalar == "C" || scalar == "Z"
    }

    private func isDigit(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 48 && scalar.value <= 57
    }
}
