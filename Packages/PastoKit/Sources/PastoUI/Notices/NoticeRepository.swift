import PastoFoundation

extension ConfigKey where Value == JSONConfigValue<[NoticeCard]> {
    /// The notice cards on show, in the order they appear.
    nonisolated static var inAppNotifications: ConfigKey<JSONConfigValue<[NoticeCard]>> {
        ConfigKey("inAppNotifications", default: JSONConfigValue([]))
    }
}

/// The notice cards on show, kept in settings so they survive a relaunch. A card the user closes
/// stays away until something adds it again.
public nonisolated struct NoticeRepository: Sendable {
    private let config: ConfigStore

    public init(config: ConfigStore) {
        self.config = config
    }

    public var cards: [NoticeCard] {
        config.value(for: .inAppNotifications).value
    }

    /// Puts the card after the ones already on show. A card with the same identifier stays as
    /// it is, where it is.
    public func add(_ card: NoticeCard) {
        var cards = cards
        guard !cards.contains(where: { $0.id == card.id }) else { return }
        cards.append(card)
        config.set(JSONConfigValue(cards), for: .inAppNotifications)
    }

    public func remove(id: NoticeCard.ID) {
        let cards = cards
        let remaining = cards.filter { $0.id != id }
        guard remaining.count != cards.count else { return }
        config.set(JSONConfigValue(remaining), for: .inAppNotifications)
    }

    /// The cards now and after every change.
    public func values() -> AsyncStream<[NoticeCard]> {
        AsyncStream { continuation in
            let task = Task {
                for await stored in config.values(for: .inAppNotifications) {
                    continuation.yield(stored.value)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
