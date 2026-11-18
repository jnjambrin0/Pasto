import Foundation
import SQLite3

/// The names of the applications or devices that have items: what search suggests as filters,
/// asked for at every keystroke.
///
/// Core Data turns "has items" (`items.@count > 0`, or any other to-many predicate) into a count
/// of every item of each application, or into a join with every item: with a year of history,
/// that reads the whole foreign-key index each time — 5 ms with the index in memory, 90 ms
/// without. This asks SQLite whether *one* item exists, which looks a single key up in the same
/// index. It reads the store with a short-lived read-only connection of its own, as
/// `StoreCompaction` writes it; the statement is checked against what Core Data returns
/// (`SourceNamesQueryTests`) and its plan is pinned (`QueryPlanTests`).
enum SourceNamesQuery {
    enum Source {
        case application
        case device

        /// The tables and columns Core Data makes of the model: `Z` and the entity's or
        /// relationship's name in capitals.
        var statement: String {
            let (table, column) = switch self {
            case .application: ("ZAPPLICATIONENTITY", "ZSOURCEAPPLICATION")
            case .device: ("ZDEVICEENTITY", "ZDEVICE")
            }
            return "SELECT DISTINCT t0.ZNAME FROM \(table) t0 WHERE t0.ZNAME IS NOT NULL"
                + " AND EXISTS (SELECT 1 FROM ZITEMENTITY t1 WHERE t1.\(column) = t0.Z_PK) ORDER BY t0.ZNAME"
        }
    }

    /// The distinct names, in ascending order; `nil` when the store cannot be read this way (a
    /// store in memory, or a database that is not what the statement expects).
    static func names(of source: Source, inStoreAt url: URL) -> [String]? {
        var handle: OpaquePointer?
        defer { sqlite3_close(handle) }
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        // Core Data's own connections may hold the database for a moment.
        sqlite3_busy_timeout(handle, 1_000)

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, source.statement, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let text = sqlite3_column_text(statement, 0) {
                    let length = Int(sqlite3_column_bytes(statement, 0))
                    names.append(String(decoding: UnsafeRawBufferPointer(start: text, count: length), as: UTF8.self))
                }
            case SQLITE_DONE:
                return names
            default:
                return nil
            }
        }
    }
}
