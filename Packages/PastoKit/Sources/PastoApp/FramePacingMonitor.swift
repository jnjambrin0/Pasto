import AppKit
import QuartzCore

/// Development instrument (`--frame-log <path>`): measures how evenly the main thread keeps up
/// with the display while the panel is on screen, and appends one summary line per second.
///
/// A display link fires once per refresh on the main run loop; when the main thread is busy the
/// callbacks arrive late, so the gap between consecutive callbacks is the time a frame took.
final class FramePacingMonitor: NSObject {
    private let logURL: URL
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var windowStart: CFTimeInterval = 0
    private var frameCount = 0
    private var longestFrame: CFTimeInterval = 0
    private var lateFrames = 0

    init(logURL: URL) {
        self.logURL = logURL
    }

    func start(in view: NSView) {
        guard displayLink == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        defer { lastTimestamp = link.timestamp }
        guard let lastTimestamp else {
            windowStart = link.timestamp
            return
        }

        let frameTime = link.timestamp - lastTimestamp
        let refreshInterval = link.targetTimestamp - link.timestamp
        frameCount += 1
        longestFrame = max(longestFrame, frameTime)
        // More than one and a half refresh intervals means at least one refresh was missed.
        if frameTime > refreshInterval * 1.5 { lateFrames += 1 }

        if link.timestamp - windowStart >= 1 {
            let line = String(
                format: "frames=%d late=%d longest_ms=%.2f refresh_ms=%.2f\n",
                frameCount, lateFrames, longestFrame * 1000, refreshInterval * 1000
            )
            append(line)
            windowStart = link.timestamp
            frameCount = 0
            lateFrames = 0
            longestFrame = 0
        }
    }

    private func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL)
        }
    }
}
