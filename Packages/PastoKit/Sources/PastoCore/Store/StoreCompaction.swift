import Foundation
import SQLite3

/// Gives the space a store no longer uses back to the disk.
///
/// SQLite keeps the pages of deleted rows for reuse instead of shrinking the file. Stores created
/// by Core Data reclaim them incrementally (`auto_vacuum = INCREMENTAL`), and Core Data itself
/// does some of it after large saves; this finishes the job after a mass deletion and once a
/// day, and converts a store that cannot reclaim space incrementally with one full `VACUUM`.
///
/// Works on its own SQLite connection beside Core Data's, which SQLite's locking keeps safe;
/// rows keep their primary keys (every Core Data table has an `INTEGER PRIMARY KEY`). It only
/// ever runs on the writer's queue, between transactions, so it never meets a capture.
enum StoreCompaction {
    struct Report: Sendable, Equatable {
        /// Pages the database had before and has after, and their size.
        var pagesBefore: Int
        var pagesAfter: Int
        var pageSize: Int
        /// Whether the whole file was rebuilt.
        var vacuumed: Bool

        var bytesReclaimed: Int64 { Int64(pagesBefore - pagesAfter) * Int64(pageSize) }
    }

    /// Reclaims nothing below this many free pages (4 MB with 4 KB pages): not worth a write.
    static var minimumFreePages: Int { 1_024 }
    /// A store without incremental reclaiming is rebuilt once a quarter of it is free.
    static var vacuumFreeRatio: Double { 0.25 }

    /// Reclaims the free pages of the database at `url` and empties its write-ahead log.
    static func compact(databaseAt url: URL) throws -> Report {
        let database = try Connection(url: url)
        let pageSize = try database.integer("PRAGMA page_size")
        let pagesBefore = try database.integer("PRAGMA page_count")
        let freeBefore = try database.integer("PRAGMA freelist_count")
        var vacuumed = false

        if freeBefore >= minimumFreePages {
            switch try database.integer("PRAGMA auto_vacuum") {
            case 2:
                // INCREMENTAL: hand back every free page.
                try database.execute("PRAGMA incremental_vacuum")
            case 0 where Double(freeBefore) >= vacuumFreeRatio * Double(pagesBefore):
                // NONE: one rebuild, which also switches the store to incremental reclaiming
                // so that it never needs another. It writes the whole database through the log.
                try database.execute("PRAGMA auto_vacuum = INCREMENTAL")
                try database.execute("VACUUM")
                vacuumed = true
            default:
                break
            }
        }
        // Folds the log into the database and truncates it; readers in the middle of a read may
        // keep part of it until next time, which is harmless.
        try database.execute("PRAGMA wal_checkpoint(TRUNCATE)")

        return Report(
            pagesBefore: pagesBefore,
            pagesAfter: try database.integer("PRAGMA page_count"),
            pageSize: pageSize,
            vacuumed: vacuumed
        )
    }

    /// A short-lived SQLite connection.
    private final class Connection {
        private var handle: OpaquePointer?

        init(url: URL) throws {
            guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
                let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open"
                sqlite3_close(handle)
                throw CompactionError(message: message)
            }
            // Core Data's own connections may hold the database for a moment.
            sqlite3_busy_timeout(handle, 10_000)
        }

        deinit {
            sqlite3_close(handle)
        }

        func execute(_ statement: String) throws {
            var error: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(handle, statement, nil, nil, &error) == SQLITE_OK else {
                defer { sqlite3_free(error) }
                throw CompactionError(message: "\(statement): \(error.map { String(cString: $0) } ?? "failed")")
            }
        }

        func integer(_ query: String) throws -> Int {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, query, -1, &statement, nil) == SQLITE_OK else {
                throw CompactionError(message: "\(query): \(String(cString: sqlite3_errmsg(handle)))")
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw CompactionError(message: "\(query): no row")
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    struct CompactionError: Error, CustomStringConvertible {
        var message: String
        var description: String { "Store compaction failed: \(message)" }
    }
}
