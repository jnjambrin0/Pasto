import Foundation

/// Timestamps shared by every probe so that logs from different processes line up.
public enum ProbeClock {
    private static let timebase: (numer: Double, denom: Double) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (Double(info.numer), Double(info.denom))
    }()

    /// Milliseconds since boot on the continuous clock (keeps counting while the Mac sleeps).
    public static func continuousMs() -> Double {
        milliseconds(fromTicks: mach_continuous_time())
    }

    /// Milliseconds since boot on the absolute clock, the one behind `NSEvent.timestamp` and CoreMedia host time.
    public static func absoluteMs() -> Double {
        milliseconds(fromTicks: mach_absolute_time())
    }

    /// Adds this to an absolute-clock reading to place it on the continuous clock.
    public static func absoluteToContinuousOffsetMs() -> Double {
        continuousMs() - absoluteMs()
    }

    public static func milliseconds(fromTicks ticks: UInt64) -> Double {
        Double(ticks) * timebase.numer / timebase.denom / 1_000_000
    }

    /// Blocks the calling thread until the continuous clock reaches `deadline`.
    public static func sleep(untilContinuousMs deadline: Double) {
        let remaining = deadline - continuousMs()
        guard remaining > 0 else { return }
        let ticks = UInt64(remaining * 1_000_000 * timebase.denom / timebase.numer)
        mach_wait_until(mach_absolute_time() + ticks)
    }

    public static func sleep(ms: Double) {
        sleep(untilContinuousMs: continuousMs() + ms)
    }

    /// Wall-clock time in ISO 8601 with milliseconds, UTC.
    public static func isoNow() -> String {
        Date.now.ISO8601Format(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    /// Rounds a millisecond value to microsecond precision for output.
    public static func rounded(_ ms: Double) -> Double {
        (ms * 1000).rounded() / 1000
    }
}
