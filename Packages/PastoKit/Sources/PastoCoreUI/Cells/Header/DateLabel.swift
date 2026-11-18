import AppKit

/// The date in a card's header: relative, and kept up to date while the card is on screen.
///
/// The text is not recomputed continuously: it is worked out when the label is given another
/// date or format, and then every 30 s, so a label can read "just now" for up to half a minute.
/// Configuring a card again with the same date leaves the text and its timer alone.
///
/// While its window is ordered out — the panel closed — the timer does not run: the label
/// remembers when it was due and, right before the window shows again, reads what it would
/// have read had the timer kept going, and goes on from there (`DateRefreshSchedule`).
final class DateLabel: NSTextField {
    var date: Date? {
        didSet {
            guard date != oldValue else { return }
            toolTip = date.map(dateFormatter.absoluteString)
            refresh()
        }
    }

    /// The abbreviated form ("2m") of the compact density.
    var isCompact = false {
        didSet {
            if isCompact != oldValue { refresh() }
        }
    }

    var clock: () -> Date = Date.init

    /// Called when the text, and so the width the label needs, has changed.
    var onTextChange: (() -> Void)?

    private let dateFormatter = ItemDateFormatter()
    private var timer: Timer?
    /// When the text is next due to be worked out again; kept while the window is ordered out.
    private var nextRefresh: Date?
    private var windowObservers: [any NSObjectProtocol] = []

    init() {
        super.init(frame: .zero)
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        alignment = .natural
        lineBreakMode = .byTruncatingTail
        allowsDefaultTighteningForTruncation = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DateLabel is created in code")
    }

    isolated deinit {
        timer?.invalidate()
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        windowObservers.forEach(NotificationCenter.default.removeObserver)
        windowObservers = []
        guard let newWindow else { return }
        let center = NotificationCenter.default
        windowObservers = [
            // Right before the window shows again: catch up before anything is drawn.
            center.addObserver(forName: WindowVisibility.willShowNotification, object: newWindow, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.resume() }
            },
            // Ordered out (or back in by other means).
            center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: newWindow, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.windowVisibilityDidChange() }
            },
        ]
    }

    /// The timer only runs while the label is in a window: a recycled or scrolled-away card
    /// must not keep waking up.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopRefreshing()
        } else {
            refresh()
        }
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
        nextRefresh = nil
    }

    /// Whether the window is ordered in. Being covered by other windows does not pause the label.
    private var isWindowShown: Bool {
        window?.isVisible ?? false
    }

    private func windowVisibilityDidChange() {
        if isWindowShown {
            resume()
        } else {
            // Paused: `nextRefresh` remembers when the text was due.
            timer?.invalidate()
            timer = nil
        }
    }

    /// Brings the text to what the refreshes missed while paused would have left, and starts
    /// the timer for the next one. Does nothing while the timer runs.
    private func resume() {
        guard timer == nil, let due = nextRefresh else { return }
        let resumption = DateRefreshSchedule.resume(due: due, now: clock())
        if let textDate = resumption.textDate {
            setText(text(at: textDate))
        }
        startTimer(due: resumption.nextDue)
    }

    private func refresh() {
        timer?.invalidate()
        timer = nil
        nextRefresh = nil
        guard date != nil else {
            setText("")
            return
        }

        let now = clock()
        setText(text(at: now))
        guard window != nil else { return }
        let due = now.addingTimeInterval(DateRefreshSchedule.interval)
        if isWindowShown {
            startTimer(due: due)
        } else {
            nextRefresh = due
        }
    }

    private func text(at now: Date) -> String {
        guard let date else { return "" }
        return isCompact ? dateFormatter.abbreviatedString(for: date, now: now) : dateFormatter.relativeString(for: date, now: now)
    }

    private func startTimer(due: Date) {
        nextRefresh = due
        let timer = Timer(timeInterval: max(0, due.timeIntervalSince(clock())), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func setText(_ text: String) {
        guard stringValue != text else { return }
        stringValue = text
        onTextChange?()
    }
}
