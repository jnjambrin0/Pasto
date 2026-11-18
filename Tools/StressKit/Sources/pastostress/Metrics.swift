import Darwin
import Foundation
import os
import SQLite3

/// The instruments every measurement reads: wall clock, resident memory, the main thread's CPU
/// time and the store's size on disk.
enum Metrics {
    /// Resident memory of this process, in bytes.
    nonisolated static func residentBytes() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : 0
    }

    /// Bytes allocated with malloc and not freed yet: what the process actually holds, unlike
    /// resident memory, which keeps pages malloc has not given back.
    nonisolated static func mallocInUse() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return statistics.size_in_use
    }

    /// The main thread's port, taken once on the main thread.
    private static let mainThread: thread_act_t = pthread_mach_thread_np(pthread_self())

    /// CPU time the main thread has used so far (user + system).
    static func mainThreadCPU() -> Duration {
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(mainThread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return .zero }
        let user = Duration.seconds(Int64(info.user_time.seconds)) + .microseconds(Int64(info.user_time.microseconds))
        let system = Duration.seconds(Int64(info.system_time.seconds)) + .microseconds(Int64(info.system_time.microseconds))
        return user + system
    }

    /// The bytes allocated on disk to the store at `url`: database, write-ahead log, shared
    /// memory and the files Core Data keeps next to it (as `StoreReader.storeSize()` counts them).
    nonisolated static func storeBytes(at url: URL) -> (database: Int64, external: Int64) {
        let name = url.lastPathComponent
        let directory = url.deletingLastPathComponent()
        let database = [name, "\(name)-wal", "\(name)-shm"].reduce(Int64(0)) { total, file in
            total + allocatedSize(of: directory.appending(path: file))
        }
        let support = directory.appending(path: ".\(url.deletingPathExtension().lastPathComponent)_SUPPORT", directoryHint: .isDirectory)
        var external: Int64 = 0
        if let enumerator = FileManager.default.enumerator(at: support, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) {
            while let file = enumerator.nextObject() as? URL {
                external += allocatedSize(of: file)
            }
        }
        return (database, external)
    }

    private nonisolated static func allocatedSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
    }

    /// The database's pages and how many of them are free, read beside Core Data.
    nonisolated static func pages(of url: URL) -> (total: Int, free: Int) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(database)
            return (0, 0)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5_000)
        func integer(_ pragma: String) -> Int {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, "PRAGMA \(pragma)", -1, &statement, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int64(statement, 0)) : 0
        }
        return (integer("page_count"), integer("freelist_count"))
    }
}

/// Measures the longest time the main thread went without serving its queue: a timer on the
/// main queue that should fire every millisecond, and the longest gap between two firings.
final class MainThreadWatchdog {
    private var timer: (any DispatchSourceTimer)?
    private var last = ContinuousClock.now
    private var longest = Duration.zero

    func start() {
        last = .now
        longest = .zero
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(1), leeway: .microseconds(100))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ContinuousClock.now
                self.longest = max(self.longest, now - self.last)
                self.last = now
            }
        }
        timer.resume()
        self.timer = timer
    }

    /// Stops watching and returns the longest gap.
    func stop() -> Duration {
        timer?.cancel()
        timer = nil
        return max(longest, ContinuousClock.now - last)
    }
}

/// Samples resident memory on its own thread and keeps the highest value seen.
final class PeakMemorySampler: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (peak: UInt64(0), running: false))

    /// Starts sampling every few milliseconds; the peak starts at the current value.
    func start() {
        state.withLock { $0 = (Metrics.residentBytes(), true) }
        let thread = Thread { [state] in
            while state.withLock({ $0.running }) {
                let resident = Metrics.residentBytes()
                state.withLock { $0.peak = max($0.peak, resident) }
                usleep(2_000)
            }
        }
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// Stops sampling and returns the peak.
    func stop() -> UInt64 {
        state.withLock { state in
            state.running = false
            return max(state.peak, Metrics.residentBytes())
        }
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }
}

/// Runs `body` and returns how long it took on the wall clock.
func measure<T>(_ body: () throws -> T) rethrows -> (result: T, time: Duration) {
    let clock = ContinuousClock()
    let start = clock.now
    let result = try body()
    return (result, clock.now - start)
}

func measure<T>(_ body: () async throws -> T) async rethrows -> (result: T, time: Duration) {
    let clock = ContinuousClock()
    let start = clock.now
    let result = try await body()
    return (result, clock.now - start)
}
