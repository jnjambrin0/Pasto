extension SystemPasteboard {
    /// A settled change of the pasteboard, as read once it stopped moving.
    public struct Change: Sendable {
        /// The change count at which the pasteboard was read.
        public let changeCount: Int
        /// How many changes this read stands for: the distance to the previous read that the
        /// capture rules did not veto. More than 1 after a burst, or after copies made in an
        /// ignored application.
        public let coveredChangeCount: Int
        /// The application that was in front when the read began.
        public let frontmostApplication: FrontmostApplication?
        /// What was read; never empty, unless `isAccessNeeded`. Items left without any
        /// representation worth keeping are not included.
        public let items: [PasteboardItemSnapshot]
        /// The pasteboard changed but was not read, because the user has not allowed Pasto to
        /// read it ("Paste from Other Apps" is not "Always Allow").
        public let isAccessNeeded: Bool
    }
}
