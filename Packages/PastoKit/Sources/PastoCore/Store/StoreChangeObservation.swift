import CoreData

/// Keeps a `StoreReader.observeChanges` callback alive; releasing it ends the observation.
@MainActor
public final class StoreChangeObservation {
    private let observer: any NSObjectProtocol

    fileprivate init(observer: any NSObjectProtocol) {
        self.observer = observer
    }

    isolated deinit {
        NotificationCenter.default.removeObserver(observer)
    }
}

extension StoreReader {
    /// Calls `onChange` after every write that reaches the reader, without saying what changed:
    /// for views that show a single item and simply read it again.
    public func observeChanges(_ onChange: @escaping @MainActor @Sendable () -> Void) -> StoreChangeObservation {
        // The view context is never written to, so every change reaches it as a merge. It is the
        // only main-queue context, which tells it apart from the background ones.
        let observer = NotificationCenter.default.addObserver(
            forName: NSManagedObjectContext.didMergeChangesObjectIDsNotification, object: nil, queue: .main
        ) { notification in
            let context = notification.object as? NSManagedObjectContext
            guard context?.concurrencyType == .mainQueueConcurrencyType else { return }
            MainActor.assumeIsolated(onChange)
        }
        return StoreChangeObservation(observer: observer)
    }
}
