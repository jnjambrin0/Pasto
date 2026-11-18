/// The step of composition that handles an item written in its stored form.
///
/// A protocol so that composition stays a pure transformation of values: the one implementation
/// the app uses, `PasteboardItemProcessor`, writes files.
protocol PasteboardItemProcessing {
    /// The pasteboard items to write for `item`. Called once per item, in the order the items are
    /// restored; `mutating` because what one item got can affect the next (file names).
    mutating func process(_ item: RestorableItem) -> [PasteboardItemSnapshot]
}
