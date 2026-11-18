import Darwin
import Foundation
import os

/// What the process costs: memory from the kernel's task counters, CPU from `getrusage`.
enum ProcessMetrics {
    /// Resident memory now and its high-water mark since the process started
    /// (`mach_task_basic_info`), in bytes.
    static func resident() -> (current: UInt64, peak: UInt64) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (info.resident_size, info.resident_size_max)
    }

    /// What Activity Monitor calls "Memory": the physical footprint, now and at its peak.
    static func footprint() -> (current: UInt64, peak: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (info.phys_footprint, UInt64(info.ledger_phys_footprint_peak))
    }

    /// Bytes the program has allocated and not freed, over every malloc zone. Unlike resident
    /// memory and footprint it drops as soon as a buffer is freed: on macOS 27 freed large blocks
    /// keep counting in both until the kernel takes the pages back.
    static func heapInUse() -> UInt64 {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return UInt64(statistics.size_in_use)
    }

    /// `ru_maxrss`: the peak resident size, in bytes on macOS.
    static func maxRSS() -> UInt64 {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return UInt64(usage.ru_maxrss)
    }

    /// User plus system CPU time consumed so far, in seconds.
    static func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ time: timeval) -> Double { Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    /// Interrupt and idle wakeups of the process so far (`task_power_info`).
    static func wakeups() -> (interrupt: UInt64, idle: UInt64) {
        var info = task_power_info()
        var count = mach_msg_type_number_t(MemoryLayout<task_power_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (info.task_interrupt_wakeups, info.task_platform_idle_wakeups)
    }
}

/// Samples resident memory and footprint every millisecond on a thread of its own, so that the
/// peak of one phase can be told apart from the process's lifetime peak.
final class PeakSampler: @unchecked Sendable {
    private struct State {
        var isRunning = false
        var residentPeak: UInt64 = 0
        var footprintPeak: UInt64 = 0
        var heapPeak: UInt64 = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private var thread: Thread?

    func start() {
        state.withLock { $0 = State(isRunning: true) }
        let thread = Thread { [state] in
            while state.withLock({ $0.isRunning }) {
                let resident = ProcessMetrics.resident().current
                let footprint = ProcessMetrics.footprint().current
                let heap = ProcessMetrics.heapInUse()
                state.withLock { state in
                    state.residentPeak = max(state.residentPeak, resident)
                    state.footprintPeak = max(state.footprintPeak, footprint)
                    state.heapPeak = max(state.heapPeak, heap)
                }
                usleep(1000)
            }
        }
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    /// Stops sampling and returns the peaks seen since `start()`.
    func stop() -> (resident: UInt64, footprint: UInt64, heap: UInt64) {
        // One last sample, so that a phase shorter than the interval is not missed.
        let resident = ProcessMetrics.resident().current
        let footprint = ProcessMetrics.footprint().current
        let heap = ProcessMetrics.heapInUse()
        return state.withLock { state in
            state.isRunning = false
            return (max(state.residentPeak, resident), max(state.footprintPeak, footprint), max(state.heapPeak, heap))
        }
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}

extension UInt64 {
    var megabytes: Double { Double(self) / 1_048_576 }
}

extension Int {
    var megabytes: Double { Double(self) / 1_048_576 }
}

/// One line of results, printed as JSON after `RESULT ` so that the driver can collect it.
struct ResultLine: Encodable {
    var scenario: String
    var values: [String: Double]
    var notes: [String: String] = [:]

    func print() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else { return }
        Swift.print("RESULT \(text)")
        fflush(stdout)
    }
}
