import Foundation
import os
import PastoCore
import PastoFoundation
import PastoRecognition

// Text recognition: an image item is indexed at once without text, and again — one image at a
// time, at low priority — with the words found in it. Those words live in the index only, so an
// image that is never read is never found by them: the queue is saved, and a launch takes it up
// where the last one left it.

extension SearchIndexer {
    /// Queues the image items among `items`, once each. Saved at once: an image missing from the
    /// saved queue would never be read.
    func enqueueForRecognition(_ items: [IndexableItem]) {
        let images = items.filter { $0.type == .image }.map(\.id)
        guard !images.isEmpty else { return }
        recognitionQueueLog.append(recognitionQueue.append(images))
    }

    func dequeueFromRecognition(_ ids: Set<ItemID>) {
        recognitionQueue.remove(ids)
        ids.forEach(recognitionQueueLog.forget)
        if recognitionQueue.isEmpty {
            recognitionQueueLog.clear()
        }
    }

    /// Puts back in the queue the images a previous run of the app left unread. A queue saved in
    /// the settings by an earlier version moves to the file.
    func restoreRecognitionQueue() {
        recognitionQueue.append(recognitionQueueLog.restore())
        let saved = config.value(for: .searchRecognitionQueue).value
        if !saved.isEmpty {
            recognitionQueueLog.append(recognitionQueue.append(saved.map(ItemID.init)))
            config.set(JSONConfigValue([]), for: .searchRecognitionQueue)
        }
    }

    /// An image has been dealt with, read or not: the saved queue lets go of it.
    private func finishRecognition(of id: ItemID) {
        recognitionQueueLog.finish(id)
        if recognitionQueue.isEmpty {
            recognitionQueueLog.clear()
        }
    }

    /// Starts the worker unless it is already at it or has nothing to do.
    func recognizeQueuedImagesIfNeeded() {
        guard isRunning, !recognitionQueue.isEmpty, recognitionTask == nil else { return }
        recognitionTask = Task(priority: .low) { [weak self] in
            await self?.recognizeQueuedImages()
        }
    }

    private func recognizeQueuedImages() async {
        defer { recognitionTask = nil }
        var isWaitingForTheMac = false
        while isRunning, !Task.isCancelled, !recognitionQueue.isEmpty {
            // Reading images can wait for a Mac on Low Power Mode, hot or nearly out of battery.
            if conditions.isConstrained {
                if !isWaitingForTheMac {
                    log.info("Text recognition waits: the Mac is saving energy or cooling down")
                    isWaitingForTheMac = true
                }
                do {
                    try await sleep(Metrics.constrainedRecheckInterval)
                } catch {
                    return
                }
                continue
            }
            isWaitingForTheMac = false
            guard let id = recognitionQueue.popFirst() else { break }
            // The saved queue lets go of an image only once it has been dealt with: one that
            // is interrupted is read again by the next launch.
            do {
                try await recognizeImage(of: id)
            } catch is CancellationError {
                recognitionQueue.putBack(id)
                return
            } catch SearchIndexError.transientlyUnavailable {
                // Back to the front; the worker starts again with the next thing the indexer does.
                log.notice("Text recognition paused at item \(id.rawValue, privacy: .public): index unavailable")
                recognitionQueue.putBack(id)
                return
            } catch {
                log.error("Text recognition failed for item \(id.rawValue, privacy: .public): \(error)")
            }
            finishRecognition(of: id)
        }
    }

    /// Indexes the item again with the words of its image. The cooldown follows every image
    /// that was actually looked at, with or without text in it — not the ones skipped.
    private func recognizeImage(of id: ItemID) async throws {
        guard let item = try await dataSource.items([id]).first else { return }
        try Task.checkCancellation()
        guard let imageData = try await dataSource.imageData(for: id) else { return }

        let words: [String]
        do {
            words = try await recognizer.recognizeWords(in: imageData)
        } catch TextRecognitionError.imageTooSmall {
            return
        } catch let error as CancellationError {
            throw error
        } catch {
            log.notice("Text recognition skipped item \(id.rawValue, privacy: .public): \(error)")
            return
        }

        let text = words.joined(separator: " ")
        if !text.isEmpty {
            try await retryingWhileTransient {
                try await index.index([SearchIndexItem(item, recognizedText: text)], isUpdate: true)
            }
        }
        log.info("Text recognition processed item \(id.rawValue, privacy: .public): \(words.count) words")
        try await sleep(Metrics.recognitionCooldown)
    }
}
