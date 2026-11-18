import ProbeCore

enum WinPollCommand: Command {
    static let name = "win-poll"
    static let summary = "Sample one window's bounds, alpha and visibility at a high rate (CSV)."
    static let usage = "win-poll (--window <id> | --app <app> --largest | --app <app> --new-at-layer <n>) [--hz 240] [--duration 2.0] [--until-change [--timeout 30]]\n"
        + "       --new-at-layer waits (up to --timeout) for a window of that layer that was not there when sampling started,\n"
        + "       such as an OSD or a popover, and samples it from the moment it exists."
    static let spec = CommandLineArguments.Spec(
        valueOptions: ["window", "app", "hz", "duration", "timeout", "new-at-layer"], flags: ["largest", "until-change"]
    )

    private struct Sample: Equatable {
        let bounds: Frame
        let alpha: Double
        let isOnscreen: Bool

        init(_ window: WindowInfo) {
            bounds = window.bounds
            alpha = window.alpha
            isOnscreen = window.isOnscreen
        }

        func row(at milliseconds: Double) -> String {
            "\(ProbeClock.rounded(milliseconds)),\(bounds.x),\(bounds.y),\(bounds.w),\(bounds.h),\(alpha),\(isOnscreen ? 1 : 0)"
        }
    }

    /// Polls until the app has a window at `layer` whose id was not present at the start.
    private static func waitForNewWindow(of app: TargetApp, layer: Int, timeoutMs: Double, periodMs: Double) throws -> WindowInfo {
        let existing = Set(WindowList.windows(ofPID: app.pid).filter { $0.layer == layer }.map(\.id))
        let start = ProbeClock.continuousMs()
        while ProbeClock.continuousMs() - start < timeoutMs {
            if let fresh = WindowList.windows(ofPID: app.pid).first(where: { $0.layer == layer && !existing.contains($0.id) }) {
                Console.error("pastoprobe: window \(fresh.id) appeared at layer \(layer)")
                return fresh
            }
            ProbeClock.sleep(ms: periodMs)
        }
        throw ProbeError.runtime("no new window at layer \(layer) within \(timeoutMs / 1000) s")
    }

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        let period = 1000 / (try arguments.positiveDouble("hz", default: 240))
        let duration = try arguments.positiveDouble("duration", default: 2) * 1000
        let timeout = try arguments.positiveDouble("timeout", default: 30) * 1000
        let window: WindowInfo
        if let layer = try arguments.int("new-at-layer") {
            window = try waitForNewWindow(of: arguments.targetApp(), layer: layer, timeoutMs: timeout, periodMs: period)
        } else {
            window = try arguments.targetWindow()
        }

        var origin = ProbeClock.continuousMs()
        var next = origin
        var baseline: (sample: Sample, time: Double)?
        var waitingForChange = arguments.flag("until-change")
        print("t_ms,x,y,w,h,alpha,onscreen")

        while true {
            let now = ProbeClock.continuousMs()
            guard let current = WindowList.window(id: window.id).map(Sample.init) else {
                Console.error("pastoprobe: window \(window.id) no longer exists; stopped sampling")
                break
            }
            if waitingForChange {
                if let baseline, baseline.sample != current {
                    // The clock starts at the first changed sample; the last unchanged one precedes it.
                    waitingForChange = false
                    origin = now
                    print(baseline.sample.row(at: baseline.time - origin))
                } else if now - origin > timeout {
                    throw ProbeError.runtime("window \(window.id) did not change within \(timeout / 1000) s")
                } else {
                    baseline = (current, now)
                }
            }
            if !waitingForChange {
                guard now - origin <= duration else { break }
                print(current.row(at: now - origin))
            }
            next = max(next + period, now)
            ProbeClock.sleep(untilContinuousMs: next)
        }
        // Lets other probes' absolute timestamps be related to this relative clock.
        Console.error("t0_continuous_ms=\(ProbeClock.rounded(origin))")
    }
}
