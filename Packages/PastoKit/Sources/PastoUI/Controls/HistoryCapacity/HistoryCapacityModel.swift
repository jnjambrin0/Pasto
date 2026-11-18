import Observation
import os
import PastoFoundation

/// The state behind a "Keep History" slider: what the knob shows, the capacity in effect, and a
/// lower limit waiting to be confirmed because it deletes items. Settings and onboarding's Quick
/// Start screen share it.
@Observable
public final class HistoryCapacityModel {
    /// Where the capacity lives. The design system knows nothing of the store, so its owner
    /// hands the three operations in.
    public struct Storage {
        let days: () -> Int
        let expiredItemCount: (_ days: Int) -> Int
        let setDays: (_ days: Int) async throws -> Void

        /// - Parameters:
        ///   - days: The capacity in effect, in days; 0 keeps everything.
        ///   - expiredItemCount: How many items a capacity of that many days would delete.
        ///   - setDays: Stores a capacity, deleting what it leaves out.
        public init(
            days: @escaping () -> Int,
            expiredItemCount: @escaping (_ days: Int) -> Int,
            setDays: @escaping (_ days: Int) async throws -> Void
        ) {
            self.days = days
            self.expiredItemCount = expiredItemCount
            self.setDays = setDays
        }
    }

    /// The capacity in effect, in days.
    public private(set) var savedDays: Int
    /// What the slider shows, which runs ahead of `savedDays` while the knob is dragged or a
    /// confirmation is pending.
    public private(set) var shownDays: Int
    /// Whether the knob is held with the mouse. Settings shows the value under the slider only
    /// then, in place of the tick names.
    public private(set) var isTracking = false
    /// A lower limit waiting for the user to accept that it deletes items.
    public private(set) var pendingDays: Int?
    /// Called once a capacity has been written, or has failed to be.
    @ObservationIgnored public var onWrite: (() -> Void)?

    /// How long the knob has to stay put after a step from the keyboard before the capacity is
    /// settled.
    static let steppedChangeDelay = Duration.milliseconds(800)

    private let storage: Storage
    private let sleep: @Sendable (Duration) async throws -> Void
    private let log = Log.logger(.store)
    /// Waits out `steppedChangeDelay` after the latest step; a newer step starts it again.
    @ObservationIgnored private(set) var steppedChange: Task<Void, Never>?

    /// - Parameter sleep: How the model waits before settling a change made a step at a time.
    public init(
        storage: Storage,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.storage = storage
        self.sleep = sleep
        let days = storage.days()
        savedDays = days
        shownDays = days
    }

    public var sliderPosition: Double {
        HistoryCapacityScale.position(forDays: shownDays)
    }

    /// Follows the knob. Nothing is stored until it is let go, and then only after asking if
    /// the new limit would delete items. Returns the position of the value the knob snapped to.
    ///
    /// - Parameters:
    ///   - isInteractive: Whether the mouse moves the knob (`HistoryCapacityScale`).
    ///   - isFinal: The knob was let go, or moved by other means than dragging.
    public func sliderMoved(to position: Double, isInteractive: Bool, isFinal: Bool) -> Double {
        // The mouse takes over from the keyboard: its release settles the value.
        cancelSteppedChange()
        shownDays = HistoryCapacityScale.days(atPosition: position, isInteractive: isInteractive, previousDays: shownDays)
        isTracking = !isFinal
        if isFinal {
            settleShownDays()
        }
        return sliderPosition
    }

    /// Follows a step from the keyboard or an assistive technology. The knob shows it at once;
    /// the capacity is settled — applied, or asked about if it deletes items — once the knob has
    /// stayed put for `steppedChangeDelay`, or when `settleSteppedChange()` says the slider lost
    /// the focus. Otherwise every arrow key on the way to the value wanted would apply one, and
    /// might ask about deleting items. Returns the position of the value the knob snapped to.
    public func sliderStepped(to position: Double) -> Double {
        shownDays = HistoryCapacityScale.days(atPosition: position, isInteractive: false, previousDays: shownDays)
        cancelSteppedChange()
        steppedChange = Task { [weak self, sleep] in
            do {
                try await sleep(Self.steppedChangeDelay)
            } catch {
                // Superseded by a newer step, by the mouse or by the focus leaving.
                return
            }
            await MainActorReturn.ensure()
            guard !Task.isCancelled else { return }
            self?.settleSteppedChange()
        }
        return sliderPosition
    }

    /// Settles a change made a step at a time without waiting any longer. Nothing to do when
    /// there is none.
    public func settleSteppedChange() {
        guard steppedChange != nil else { return }
        cancelSteppedChange()
        settleShownDays()
    }

    private func cancelSteppedChange() {
        steppedChange?.cancel()
        steppedChange = nil
    }

    /// Applies what the knob shows, or keeps it pending if it deletes items.
    private func settleShownDays() {
        if storage.expiredItemCount(shownDays) > 0 {
            pendingDays = shownDays
        } else {
            apply(shownDays)
        }
    }

    public func confirmPendingCapacity() {
        guard let pendingDays else { return }
        self.pendingDays = nil
        apply(pendingDays)
    }

    /// Puts the knob back on the capacity in effect. Nothing to do once the pending limit was
    /// settled either way.
    public func discardPendingCapacity() {
        guard pendingDays != nil else { return }
        pendingDays = nil
        shownDays = savedDays
    }

    /// Storing the capacity in effect again changes nothing, so it is not written.
    private func apply(_ days: Int) {
        shownDays = days
        guard days != savedDays else { return }
        savedDays = days
        Task {
            do {
                try await storage.setDays(days)
                await MainActorReturn.ensure()
            } catch {
                await MainActorReturn.ensure()
                log.error("Could not change the history capacity: \(error)")
                // The change did not happen: go back to what the store says.
                savedDays = storage.days()
                shownDays = savedDays
            }
            onWrite?()
        }
    }
}
