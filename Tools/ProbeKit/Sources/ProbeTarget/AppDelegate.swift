import AppKit
import ProbeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate, NSTextFieldDelegate {
    private let options: TargetOptions
    private let log: EventLog

    private var window: NSWindow?
    private let textView = ProbeTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
    private let fieldEditor = ProbeTextView(frame: .zero)
    private let textField = NSTextField(string: "")
    private let secureField = NSSecureTextField(string: "")

    private var keyMonitor: Any?
    private var signalSources: [DispatchSourceSignal] = []
    private var lazySource: LazyCopySource?
    private var lazyCopyCount = 0

    init(options: TargetOptions, log: EventLog) {
        self.options = options
        self.log = log
    }

    // MARK: Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMainMenu()
        let window = makeWindow()
        self.window = window
        installKeyMonitor()
        installSignalHandlers()

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(textView)
        NSApp.activate(ignoringOtherApps: true)
        if options.fullscreen { window.toggleFullScreen(nil) }

        log.record("launched", ["pid": Int(ProcessInfo.processInfo.processIdentifier), "windowId": window.windowNumber])
        Console.out(JSONText.line([
            "log": log.url.path,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
            "windowId": window.windowNumber,
        ]))
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Lifecycle events

    func applicationDidBecomeActive(_ notification: Notification) { log.record("didBecomeActive") }
    func applicationDidResignActive(_ notification: Notification) { log.record("didResignActive") }
    func applicationWillTerminate(_ notification: Notification) { log.record("willTerminate") }
    func windowDidBecomeKey(_ notification: Notification) { log.record("windowDidBecomeKey") }
    func windowDidResignKey(_ notification: Notification) { log.record("windowDidResignKey") }

    // MARK: Text changes (lengths only, never content)

    func textDidChange(_ notification: Notification) {
        log.record("textDidChange", ["target": "textView", "length": textView.textStorage?.length ?? 0])
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        let target = field === secureField ? "secureField" : "textField"
        log.record("textDidChange", ["target": target, "length": field.stringValue.utf16.count])
    }

    /// Gives the plain text field a logging field editor. The secure field keeps the system one.
    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        (client as AnyObject?) === textField ? fieldEditor : nil
    }

    // MARK: Lazy copy source

    @objc private func copyLazyString(_ sender: Any?) {
        guard let delayMs = options.lazyCopyDelayMs else { return }
        lazyCopyCount += 1
        let source = LazyCopySource(delayMs: delayMs, sequence: lazyCopyCount, log: log)
        lazySource = source
        source.copy()
    }

    // MARK: Input monitoring

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [log] event in
            log.record(Self.name(of: event.type), Self.describe(event))
            return event
        }
    }

    private static func name(of type: NSEvent.EventType) -> String {
        switch type {
        case .keyDown: "keyDown"
        case .keyUp: "keyUp"
        default: "flagsChanged"
        }
    }

    private static func describe(_ event: NSEvent) -> [String: Any] {
        var fields: [String: Any] = [
            "keyCode": Int(event.keyCode),
            "modifierFlags": event.modifierFlags.rawValue,
            "modifiers": modifierNames(event.modifierFlags),
            // When the event was created, moved onto the same clock as t_ms.
            "event_t_ms": ProbeClock.rounded(event.timestamp * 1000 + ProbeClock.absoluteToContinuousOffsetMs()),
        ]
        if event.type != .flagsChanged {
            fields["characters"] = event.characters ?? ""
            fields["charactersIgnoringModifiers"] = event.charactersIgnoringModifiers ?? ""
            fields["isARepeat"] = event.isARepeat
        }
        if let cgEvent = event.cgEvent {
            fields["sourcePid"] = cgEvent.getIntegerValueField(.eventSourceUnixProcessID)
            fields["sourceStateID"] = cgEvent.getIntegerValueField(.eventSourceStateID)
            fields["sourceUserData"] = cgEvent.getIntegerValueField(.eventSourceUserData)
        }
        return fields
    }

    private static func modifierNames(_ flags: NSEvent.ModifierFlags) -> [String] {
        let names: [(NSEvent.ModifierFlags, String)] = [
            (.command, "command"), (.shift, "shift"), (.option, "option"), (.control, "control"),
            (.function, "function"), (.capsLock, "capsLock"), (.numericPad, "numericPad"),
        ]
        return names.filter { flags.contains($0.0) }.map(\.1)
    }

    private func installSignalHandlers() {
        signalSources = [SIGTERM, SIGINT].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [log] in
                log.record("signal", ["number": Int(number)])
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
            source.resume()
            return source
        }
    }

    // MARK: Window

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = options.title
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        if options.floating { window.level = .floating }
        window.contentView = makeContentView()
        if let frame = options.frame, let primary = NSScreen.screens.first {
            // Options use a top-left origin; AppKit measures from the bottom of the primary screen.
            let origin = NSPoint(x: frame.x, y: primary.frame.height - frame.y - frame.h)
            window.setFrame(NSRect(origin: origin, size: NSSize(width: frame.w, height: frame.h)), display: false)
        } else {
            window.center()
        }
        return window
    }

    private func makeContentView() -> NSView {
        textField.placeholderString = "Single-line text field"
        textField.delegate = self
        textField.setAccessibilityIdentifier("probe.textField")
        secureField.placeholderString = "Secure text field"
        secureField.delegate = self
        secureField.setAccessibilityIdentifier("probe.secureField")

        for editor in [textView, fieldEditor] {
            editor.log = log
            editor.isRichText = true
            editor.allowsUndo = true
        }
        fieldEditor.isFieldEditor = true
        fieldEditor.targetName = "textField"

        textView.delegate = self
        textView.clearsAfterPaste = options.clearOnPaste
        textView.importsGraphics = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityIdentifier("probe.textView")

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = textView

        var rows: [NSView] = [textField, secureField]
        if let delayMs = options.lazyCopyDelayMs {
            let button = NSButton(title: "Copy lazy string (\(delayMs) ms)", target: self, action: #selector(copyLazyString(_:)))
            button.setAccessibilityIdentifier("probe.copyLazyButton")
            rows.append(button)
        }
        rows.append(scrollView)

        // Rows stacked top to bottom; the scroll view, last, takes whatever height is left.
        let container = NSView()
        let margin: CGFloat = 12
        var above = container.topAnchor
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(row)
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: above, constant: row === rows.first ? margin : 8),
                row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: margin),
            ])
            if !(row is NSButton) {
                row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -margin).isActive = true
            }
            above = row.bottomAnchor
        }
        scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -margin).isActive = true
        return container
    }

    // MARK: Menu

    /// Standard Edit commands matter: Cmd-V only reaches `paste(_:)` through a menu key equivalent.
    private func makeMainMenu() -> NSMenu {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ProbeTarget", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pasteAndMatchStyle = editMenu.addItem(
            withTitle: "Paste and Match Style", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "V"
        )
        pasteAndMatchStyle.keyEquivalentModifierMask = [.command, .option, .shift]
        editMenu.addItem(withTitle: "Delete", action: #selector(NSText.delete(_:)), keyEquivalent: "")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        if options.lazyCopyDelayMs != nil {
            editMenu.addItem(.separator())
            let lazyCopy = editMenu.addItem(withTitle: "Copy Lazy String", action: #selector(copyLazyString(_:)), keyEquivalent: "l")
            lazyCopy.keyEquivalentModifierMask = [.command, .shift]
            lazyCopy.target = self
        }

        let mainMenu = NSMenu()
        for submenu in [appMenu, editMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            mainMenu.addItem(item)
        }
        return mainMenu
    }
}
