import CoreData
import Foundation
@testable import PastoCore
import PastoFoundation
import Testing

/// `ListCollection` learns what changed from the view context's merge notification. Nothing keeps
/// the lists loaded in the view context; the notification must — and does — name every object
/// the save changed, loaded or not.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ListCollectionTests {
    private let store: StoreFixture

    init() throws {
        store = try StoreFixture()
    }

    /// Lets go of every object the view context holds, so that the next merge finds none of them.
    private func forgetEverythingLoaded() {
        let viewContext = store.stack.container.viewContext
        viewContext.reset()
        #expect(viewContext.registeredObjects.isEmpty)
    }

    @Test func listsTheViewContextHasNotLoadedAreFollowedToo() async throws {
        let (work, home) = try await store.writer.perform(author: .user) { context in
            (try context.createPinboard(name: "Work", color: .blue), try context.createPinboard(name: "Home", color: .red))
        }
        let lists = store.reader.listCollection()
        #expect(lists.snapshot == CollectionSnapshot(ids: [.clipboard, work, home]))
        // Nothing of the lists stays loaded in the view context.
        forgetEverythingLoaded()

        let renamed = try await lists.change {
            try await store.writer.perform(author: .user) { try $0.renameList(home, to: "Family") }
        }
        #expect(renamed.snapshot == CollectionSnapshot(ids: [.clipboard, work, home], updatedIDs: [home]))
        forgetEverythingLoaded()

        let reordered = try await lists.change {
            try await store.writer.perform(author: .user) { try $0.reorderLists([.clipboard, home, work]) }
        }
        #expect(reordered.snapshot == CollectionSnapshot(ids: [.clipboard, home, work]))
        forgetEverythingLoaded()

        let deleted = try await lists.change {
            try await store.writer.perform(author: .user) { try $0.deleteList(work) }
        }
        #expect(deleted.snapshot == CollectionSnapshot(ids: [.clipboard, home]))
        #expect(lists.snapshot == deleted.snapshot)
    }

    @Test func aWriteThatTouchesNoListPublishesNothing() async throws {
        let pinboard = try await store.writer.perform(author: .user) { try $0.createPinboard(name: "Work", color: .blue) }
        let lists = store.reader.listCollection()
        var published: [CollectionSnapshot<ListID>] = []
        lists.onChange = { published.append($0) }

        _ = try await store.record(["a", "b"])
        await lists.settle()
        #expect(published.isEmpty)

        // The next change that does touch a list is the first one published.
        let renamed = try await lists.change {
            try await store.writer.perform(author: .user) { try $0.renameList(pinboard, to: "Home") }
        }
        #expect(renamed.snapshot == CollectionSnapshot(ids: [.clipboard, pinboard], updatedIDs: [pinboard]))
    }
}
