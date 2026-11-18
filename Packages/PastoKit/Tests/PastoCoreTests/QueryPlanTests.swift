import Foundation
@testable import PastoCore
import Testing

/// The queries that run on every capture, every list and every retention find an index instead
/// of reading the whole item table, which carries the previews.
///
/// The statements are the ones Core Data issues for `ItemListQuery` (taken from its SQL log), and
/// the plans are SQLite's for a store of the current model. Without statistics — Core Data does
/// not gather them — SQLite plans the same for an empty table as for a year of items.
@Suite(.timeLimit(.minutes(1)))
struct QueryPlanTests {
    private let folder = TemporaryFolder()

    private func plans() throws -> [String: String] {
        _ = try PersistentStack(location: .onDisk(folder.storeURL), deviceName: "Mac", appVersion: "1.0")
        let database = SQLiteInspector(url: folder.storeURL)
        let statements = [
            // The history as the item collection reads it, and its newest items (each capture;
            // suggestions).
            "history": "SELECT 4, t0.Z_PK, t0.ZIDENTIFIER, t0.ZTIMESTAMP FROM ZITEMENTITY t0 WHERE t0.ZTIMESTAMP IS NOT NULL ORDER BY t0.ZTIMESTAMP DESC, t0.ZIDENTIFIER DESC",
            "newest": "SELECT 0, t0.Z_PK, t0.ZRAWPREVIEW FROM ZITEMENTITY t0 WHERE t0.ZTIMESTAMP IS NOT NULL ORDER BY t0.ZTIMESTAMP DESC, t0.ZIDENTIFIER DESC LIMIT 40",
            "historyCount": "SELECT COUNT(t0.Z_PK) FROM ZITEMENTITY t0 WHERE t0.ZTIMESTAMP IS NOT NULL",
            // Retention: what expires, and how much would.
            "expiring": "SELECT 0, t0.Z_PK FROM ZITEMENTITY t0 WHERE ( t0.ZLIST IS NULL AND t0.ZTIMESTAMP < 1)",
            "expiringCount": "SELECT COUNT(t0.Z_PK) FROM ZITEMENTITY t0 WHERE ( t0.ZLIST IS NULL AND t0.ZTIMESTAMP < 1)",
            // A pinboard in its order.
            "pinboard": "SELECT 4, t0.Z_PK, t0.ZIDENTIFIER, t0.ZTIMESTAMP, t0.ZDISPLAYORDERINPINBOARD FROM ZITEMENTITY t0 JOIN ZLISTENTITY t1 ON t0.ZLIST = t1.Z_PK WHERE t1.ZIDENTIFIER = 'x' ORDER BY t0.ZDISPLAYORDERINPINBOARD, t0.ZTIMESTAMP DESC, t0.ZIDENTIFIER DESC",
            // The item a capture is a copy of.
            "checksum": "SELECT 0, t0.Z_PK FROM ZITEMENTITY t0 WHERE t0.ZCHECKSUM = 'x' ORDER BY t0.ZTIMESTAMP DESC LIMIT 1",
            // The applications and devices search suggests (at every keystroke).
            "applicationNames": SourceNamesQuery.Source.application.statement,
            "deviceNames": SourceNamesQuery.Source.device.statement,
        ]
        return try statements.mapValues(database.plan)
    }

    @Test func everyListQueryUsesAnIndex() throws {
        let plans = try plans()

        // Read from the index alone, backwards: no sorting, no rows.
        #expect(plans["history"] == "SEARCH t0 USING COVERING INDEX Z_ItemEntity_byTimestamp (ZTIMESTAMP>?)")
        #expect(plans["newest"] == "SEARCH t0 USING INDEX Z_ItemEntity_byTimestamp (ZTIMESTAMP>?)")
        #expect(plans["historyCount"]?.contains("COVERING INDEX") == true)
        #expect(plans["expiring"]?.contains("Z_ItemEntity_byListAndTimestamp (ZLIST=? AND ZTIMESTAMP<?)") == true)
        #expect(plans["expiringCount"]?.contains("COVERING INDEX Z_ItemEntity_byListAndTimestamp") == true)
        #expect(plans["pinboard"]?.contains("Z_ItemEntity_byListAndDisplayOrder (ZLIST=?)") == true)
        #expect(plans["checksum"]?.contains("Z_ItemEntity_byChecksum") == true)
        // One key looked up per application or device, not every item of each counted.
        #expect(plans["applicationNames"]?.contains(
            "SEARCH t1 EXISTS USING COVERING INDEX ZITEMENTITY_ZSOURCEAPPLICATION_INDEX (ZSOURCEAPPLICATION=?)"
        ) == true)
        #expect(plans["deviceNames"]?.contains("SEARCH t1 EXISTS USING COVERING INDEX ZITEMENTITY_ZDEVICE_INDEX (ZDEVICE=?)") == true)
        // Nothing reads the item table from end to end. Only the small sets a pinboard or a
        // checksum finds are sorted after the fact, and the handful of names.
        for (query, plan) in plans {
            #expect(!plan.contains("SCAN t1"), "\(query): \(plan)")
            #expect(!plan.contains("SCAN t0") || plan.contains("INDEX") || query.hasSuffix("Names"), "\(query): \(plan)")
            if !["pinboard", "checksum", "applicationNames", "deviceNames"].contains(query) {
                #expect(!plan.contains("TEMP B-TREE"), "\(query): \(plan)")
            }
        }
    }
}
