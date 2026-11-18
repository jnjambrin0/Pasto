import Foundation
import PastoCore
import PastoFoundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LinkMetadataTests {
    /// Answers every request with the same metadata and reports the addresses it was asked about.
    private struct Provider: LinkMetadataProviding {
        let answer: LinkMetadata?
        let requests: AsyncStream<URL>.Continuation

        func metadata(for url: URL) async -> LinkMetadata? {
            requests.yield(url)
            return answer
        }
    }

    private let address = "https://ejemplo.com/pagina"

    private func link(at second: TimeInterval, title: String? = nil) throws -> NewItem {
        NewItem(
            type: .link,
            checksum: address,
            preview: .link(LinkPreview(url: try #require(URL(string: address)), title: title)),
            pasteboardItems: [PasteboardItemSnapshot(strings: ["public.utf8-plain-text": address])],
            timestamp: .second(second)
        )
    }

    @MainActor
    @Test func thePageReplacesWhatTheLinkWasCopiedWith() async throws {
        let store = try StoreFixture()
        let item = try link(at: 1, title: "Copied name")
        let id = try await store.writer.perform(author: .capture) { try $0.record(item).id }

        let metadata = LinkMetadata(title: nil, iconData: Data([1]), imageData: Data([2]))
        let url = try #require(URL(string: address))
        try await store.writer.perform(author: .capture) { try $0.setLinkMetadata(metadata, of: id, for: url) }

        let stored = try #require(store.reader.item(id))
        #expect(stored.preview == .link(LinkPreview(
            url: try #require(URL(string: address)), title: nil, iconData: Data([1]), imageData: Data([2])
        )))
        // Its place in the history does not change.
        #expect(stored.timestamp == .second(1))
    }

    @MainActor
    @Test func metadataForAnItemThatIsGoneOrIsNotALinkIsDropped() async throws {
        let store = try StoreFixture()
        let textID = try await store.record(["a"])[0]
        let url = try #require(URL(string: address))

        try await store.writer.perform(author: .capture) { context in
            try context.setLinkMetadata(LinkMetadata(title: "x"), of: textID, for: url)
            try context.setLinkMetadata(LinkMetadata(title: "x"), of: ItemID(rawValue: "gone"), for: url)
        }

        #expect(store.reader.item(textID)?.preview == .text(TextPreview(text: "a", characterCount: 1)))
    }

    @MainActor
    @Test func metadataForAnotherAddressThanTheLinkHasNowIsDropped() async throws {
        let store = try StoreFixture()
        let id = try await store.writer.perform(author: .capture) { [self] in try $0.record(try link(at: 1)).id }
        let edited = try #require(URL(string: "https://ejemplo.com/otra"))
        try await store.writer.perform(author: .user) { try $0.replaceContent(of: id, with: NewItem(
            type: .link,
            checksum: edited.absoluteString,
            preview: .link(LinkPreview(url: edited)),
            pasteboardItems: [],
            timestamp: .second(2)
        )) }

        let requested = try #require(URL(string: address))
        try await store.writer.perform(author: .capture) {
            try $0.setLinkMetadata(LinkMetadata(title: "Old page"), of: id, for: requested)
        }

        #expect(store.reader.item(id)?.preview == .link(LinkPreview(url: edited)))
    }

    @MainActor
    @Test func copyingALinkAgainStartsFromAFreshPreview() async throws {
        let store = try StoreFixture()
        let first = try link(at: 1)
        let id = try await store.writer.perform(author: .capture) { try $0.record(first).id }
        let url = try #require(URL(string: address))
        try await store.writer.perform(author: .capture) {
            try $0.setLinkMetadata(LinkMetadata(title: "Page", imageData: Data([2])), of: id, for: url)
        }

        let again = try link(at: 2)
        let outcome = try await store.writer.perform(author: .capture) { try $0.record(again) }

        #expect(outcome.id == id)
        #expect(store.reader.item(id)?.preview == .link(LinkPreview(url: try #require(URL(string: address)))))
    }

    @MainActor
    @Test func aLinkCanBeAskedAboutAgainOutsideACapture() async throws {
        let (requests, continuation) = AsyncStream.makeStream(of: URL.self)
        let page = LinkMetadata(title: "Page", iconData: Data([1]), imageData: Data([2]))
        let fixture = try await CaptureFixture(starts: false, linkMetadataProvider: Provider(answer: page, requests: continuation))
        let url = try #require(URL(string: address))
        let item = try link(at: 1)
        let id = try await fixture.store.writer.perform(author: .user) { try $0.record(item).id }

        // Off: nothing is asked and nothing changes.
        fixture.config.set(false, for: .isLinkPreviewsEnabled)
        await fixture.manager.fetchLinkMetadata(of: url, for: id)
        #expect(fixture.store.reader.item(id)?.preview == .link(LinkPreview(url: url)))

        fixture.config.set(true, for: .isLinkPreviewsEnabled)
        await fixture.manager.fetchLinkMetadata(of: url, for: id)
        #expect(fixture.store.reader.item(id)?.preview == .link(LinkPreview(
            url: url, title: "Page", iconData: Data([1]), imageData: Data([2])
        )))
        continuation.finish()
        var asked: [URL] = []
        for await request in requests { asked.append(request) }
        #expect(asked == [url])
    }

    @Test func capturingALinkAsksForItsPage() async throws {
        let (requests, continuation) = AsyncStream.makeStream(of: URL.self)
        let fixture = try await CaptureFixture(linkMetadataProvider: Provider(answer: nil, requests: continuation))

        _ = await fixture.copy(address)

        var iterator = requests.makeAsyncIterator()
        #expect(await iterator.next() == URL(string: address))
    }
}
