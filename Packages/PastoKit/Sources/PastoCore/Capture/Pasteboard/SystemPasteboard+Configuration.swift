import Foundation

extension SystemPasteboard {
    /// The timings and limits of monitoring. `standard` is what the app runs with; tests shorten the waits.
    public struct Configuration: Sendable {
        /// How often the change count is sampled.
        public var pollInterval: DispatchTimeInterval
        public var pollLeeway: DispatchTimeInterval
        /// How long after the last detected change the pasteboard is read; every new change
        /// restarts the wait (applications often write in bursts).
        public var settleDelay: DispatchTimeInterval
        /// Upper bound for the bytes kept from one read, over all items and types;
        /// representations that would exceed it are skipped and do not count.
        public var maximumCaptureSize: Int
        /// How long a read vetoed by the capture rules keeps supplying the reference from which
        /// the next read counts the changes it covers.
        public var droppedSyncWindow: TimeInterval

        public init(
            pollInterval: DispatchTimeInterval,
            pollLeeway: DispatchTimeInterval,
            settleDelay: DispatchTimeInterval,
            maximumCaptureSize: Int,
            droppedSyncWindow: TimeInterval
        ) {
            self.pollInterval = pollInterval
            self.pollLeeway = pollLeeway
            self.settleDelay = settleDelay
            self.maximumCaptureSize = maximumCaptureSize
            self.droppedSyncWindow = droppedSyncWindow
        }

        /// The timings and limits the app runs with.
        public static let standard = Configuration(
            pollInterval: .milliseconds(250),
            pollLeeway: .milliseconds(25),
            settleDelay: .milliseconds(300),
            maximumCaptureSize: 1 << 30,
            droppedSyncWindow: 1
        )
    }
}
