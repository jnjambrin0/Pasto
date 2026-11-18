import Foundation
import Observation
import os
import PastoCore
import PastoFoundation
import PastoUI

/// "Keep History": the capacity of the clipboard history, what the store holds and erasing it.
/// The capacity lives in the store, not in settings.
@Observable
final class HistoryModel {
    /// How long the store has to stay still before the summary is measured again.
    private static let summaryDelay: Duration = .seconds(1)

    let capacity: HistoryCapacityModel
    private(set) var itemCount = 0
    private(set) var storeSize: Int64 = 0

    private let reader: StoreReader
    private let writer: StoreWriter
    private let didChangeItemsIrreversibly: () -> Void
    private let didEraseHistory: () -> Void
    private let log = Log.logger(.store)
    /// The numbers are measured again after the store changes, once the change has reached the
    /// reader: a count taken when a write returns can still be the one before it.
    @ObservationIgnored private var storeObservation: StoreChangeObservation?
    @ObservationIgnored private var summaryUpdate: Task<Void, Never>?

    /// - Parameter didChangeItemsIrreversibly: Called when the user erases or shortens the
    ///   history, which cannot be undone and leaves earlier changes to items beyond undoing.
    ///   `didEraseHistory` is called once an erase has been saved.
    init(
        reader: StoreReader,
        writer: StoreWriter,
        didChangeItemsIrreversibly: @escaping () -> Void,
        didEraseHistory: @escaping () -> Void
    ) {
        self.didEraseHistory = didEraseHistory
        self.reader = reader
        self.writer = writer
        self.didChangeItemsIrreversibly = didChangeItemsIrreversibly
        capacity = HistoryCapacityModel(storage: HistoryCapacityModel.Storage(
            days: { reader.historyCapacity.days },
            expiredItemCount: { reader.expiredHistoryItemCount(for: HistoryCapacity(days: $0)) },
            setDays: { days in
                try await writer.perform(author: .user) { _ = try $0.setHistoryCapacity(HistoryCapacity(days: days)) }
            }
        ))
        capacity.onWrite = didChangeItemsIrreversibly
        updateStorageSummary(after: nil)
        storeObservation = reader.observeChanges { [weak self] in
            self?.updateStorageSummary(after: Self.summaryDelay)
        }
    }

    isolated deinit {
        summaryUpdate?.cancel()
    }

    func eraseHistory() {
        didChangeItemsIrreversibly()
        Task { [writer, log, didEraseHistory] in
            do {
                try await writer.perform(author: .user) { _ = try $0.eraseHistory() }
                didEraseHistory()
            } catch {
                log.error("Could not erase the history: \(error)")
            }
        }
    }

    /// Measures the store again, once it has been still for `delay`: a burst of changes is
    /// measured once, and a measurement under way gives way to the next.
    private func updateStorageSummary(after delay: Duration?) {
        summaryUpdate?.cancel()
        summaryUpdate = Task { [weak self, reader] in
            if let delay {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            // Measuring the store reads the disk, so it happens off the main actor.
            let size = await reader.storeSize()
            guard !Task.isCancelled, let self else { return }
            itemCount = reader.totalItemCount()
            storeSize = size
        }
    }
}
