import Foundation
import os
import PastoCore
import PastoFoundation

/// Asks the language model about copied texts the rules could not classify, one at a time and
/// a moment after each was copied.
///
/// Its answer — even "none of those" — goes to the class store, so that no text is asked about
/// twice. A failed question stores nothing: the text is asked about again if it is copied again.
/// A text copied again while it waits takes the place of the waiting one and waits again; once
/// its wait has started it is no longer in the queue, so copying it again then queues a second
/// question.
actor LanguageModelItemClassifier {
    private struct Request {
        var item: ItemID
        var text: String
        var readyAt: ContinuousClock.Instant
    }

    private let store: ItemClassStore
    private let client: any LanguageModelClient
    private let debounce: Duration
    private let log = Log.logger(.picks)
    private var pending: [Request] = []
    private var worker: Task<Void, Never>?
    /// Tells a worker that was let go from the one that replaced it.
    private var workerGeneration = 0

    init(store: ItemClassStore, client: any LanguageModelClient, debounce: Duration = PicksMetrics.classificationDebounce) {
        self.store = store
        self.client = client
        self.debounce = debounce
    }

    /// Whether a copied text is worth the model's time: neither too short nor too long, and
    /// left unclassified by the rules.
    static func isWorthAsking(_ text: String) -> Bool {
        PicksMetrics.modelTextLengths.contains(text.count)
            && ItemClassRules.itemClass(of: text, type: .text) == .unclassified
    }

    /// Queues `text`, the text of `item`, unless it is not worth asking about, the model is not
    /// available or the item was already classified. An item already in the queue leaves it and
    /// joins again at the back, with the new text and a new wait.
    func enqueue(_ item: ItemID, text: String) async {
        guard Self.isWorthAsking(text), client.availability == .available,
              await !store.hasModelClass(for: item)
        else { return }

        pending.removeAll { $0.item == item }
        pending.append(Request(item: item, text: text, readyAt: .now + debounce))
        guard worker == nil else { return }
        workerGeneration += 1
        let generation = workerGeneration
        worker = Task { await self.work(generation) }
    }

    /// Drops the queue and lets the worker go.
    func cancelAll() {
        worker?.cancel()
        worker = nil
        pending = []
    }

    /// Loads the model, then asks about each request once its wait is over, in order.
    private func work(_ generation: Int) async {
        client.prewarm()
        while !pending.isEmpty, !Task.isCancelled {
            let request = pending.removeFirst()
            try? await Task.sleep(until: request.readyAt, clock: .continuous)
            guard !Task.isCancelled else { break }
            await classify(request)
        }
        if generation == workerGeneration {
            worker = nil
        }
    }

    private func classify(_ request: Request) async {
        let itemClass: ItemClass
        do {
            itemClass = try await client.classify(request.text)
        } catch {
            log.info("Language model left an item unclassified: \(error)")
            return
        }
        guard !Task.isCancelled else { return }
        do {
            try await store.setModelClass(itemClass, for: request.item)
        } catch {
            log.error("Could not store the class of an item: \(error)")
        }
    }
}
