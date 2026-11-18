import Foundation
import PastoFoundation
import PastoUI
import Testing

/// The notice cards on show, kept in settings so they survive a relaunch.
struct NoticeRepositoryTests {
    private let ephemeral = EphemeralDefaults()
    private var repository: NoticeRepository { NoticeRepository(config: ConfigStore(defaults: ephemeral.defaults)) }

    private func card(_ id: String, title: String = "Title") -> NoticeCard {
        NoticeCard(
            id: id,
            symbol: "power",
            title: title,
            description: "Description",
            action: NoticeCard.Action(title: "Enable", command: .enableOpenAtLogin)
        )
    }

    @Test func thereAreNoCardsToBeginWith() {
        #expect(repository.cards.isEmpty)
    }

    @Test func cardsAreKeptInTheOrderTheyWereAdded() {
        repository.add(card("first"))
        repository.add(card("second"))

        #expect(repository.cards == [card("first"), card("second")])
    }

    @Test func addingACardThatIsAlreadyThereChangesNothing() {
        repository.add(card("first"))
        repository.add(card("second"))
        repository.add(card("first", title: "Another title"))

        #expect(repository.cards == [card("first"), card("second")])
    }

    @Test func aRemovedCardIsGoneAndTheOthersStay() {
        repository.add(card("first"))
        repository.add(card("second"))
        repository.remove(id: "first")

        #expect(repository.cards == [card("second")])
    }

    @Test func aCardThatWasRemovedCanBeAddedAgain() {
        repository.add(card("first"))
        repository.remove(id: "first")
        repository.add(card("first"))

        #expect(repository.cards == [card("first")])
    }

    @Test func changesAreAnnounced() async {
        var iterator = repository.values().makeAsyncIterator()
        #expect(await iterator.next() == [])

        repository.add(card("first"))

        #expect(await iterator.next() == [card("first")])
    }
}
