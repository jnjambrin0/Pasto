import Foundation

/// How often the store is looked after and how much persistent history it keeps.
public enum StoreMaintenancePolicy {
    /// Persistent history older than this goes, except what a consumer has not been given yet.
    /// Long enough for a consumer that was not running for a few days to resume where it left
    /// off instead of rebuilding.
    public static let historyWindow: TimeInterval = 7 * 24 * 60 * 60

    /// How long between two rounds of maintenance while Pasto runs.
    public static let interval: Duration = .seconds(24 * 60 * 60)
}
