import AppKit
import ProbeCore

/// A text view that logs every paste: what the pasteboard offered before, how much text arrived after.
/// It serves both as the main editor and as the field editor of the single-line text field.
final class ProbeTextView: NSTextView {
    var log: EventLog?
    /// Name of the control this view edits, as it appears in the log.
    var targetName = "textView"
    var clearsAfterPaste = false

    private struct PendingPaste {
        let action: String
        let lengthBefore: Int
        let selectedLength: Int
    }

    override func paste(_ sender: Any?) {
        let pending = beginPaste("paste")
        super.paste(sender)
        endPaste(pending)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        let pending = beginPaste("pasteAsPlainText")
        super.pasteAsPlainText(sender)
        endPaste(pending)
    }

    override func pasteAsRichText(_ sender: Any?) {
        let pending = beginPaste("pasteAsRichText")
        super.pasteAsRichText(sender)
        endPaste(pending)
    }

    // MARK: Drops

    /// Logs what a drag offers when it first enters the view: operation mask and, per item, every type
    /// with its size and, for textual types and the source's private identifiers, the first characters.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let operation = super.draggingEntered(sender)
        log?.record("dragEntered", [
            "target": targetName,
            "sourceOperationMask": sender.draggingSourceOperationMask.rawValue,
            "accepted": operation.rawValue,
            "items": Self.describeDragItems(sender.draggingPasteboard),
        ])
        return operation
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let lengthBefore = textStorage?.length ?? 0
        let accepted = super.performDragOperation(sender)
        log?.record("drop", [
            "target": targetName,
            "accepted": accepted,
            "insertedLength": (textStorage?.length ?? 0) - lengthBefore,
            "lengthAfter": textStorage?.length ?? 0,
        ])
        return accepted
    }

    private static func describeDragItems(_ pasteboard: NSPasteboard) -> [[String: Any]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            ["types": item.types.map { type -> [String: Any] in
                var entry: [String: Any] = ["type": type.rawValue]
                if let data = item.data(forType: type) { entry["bytes"] = data.count }
                let raw = type.rawValue
                if raw.contains("text") || raw.contains("url") || raw.contains("item-id") || raw.contains("html") {
                    if let string = item.string(forType: type) { entry["preview"] = String(string.prefix(80)) }
                }
                return entry
            }]
        }
    }

    // MARK: Pastes

    private func beginPaste(_ action: String) -> PendingPaste {
        let arrival = ProbeClock.continuousMs()
        // Measuring every representation makes the source app produce any data it only promised.
        let snapshot = PasteboardInspector.snapshot()
        let pending = PendingPaste(
            action: action, lengthBefore: textStorage?.length ?? 0, selectedLength: selectedRange().length
        )
        log?.record("pasteBegin", [
            "action": action,
            "target": targetName,
            "changeCount": snapshot.changeCount,
            "accessBehavior": snapshot.accessBehavior,
            "items": snapshot.itemsAsJSONObject,
            "inspectMs": ProbeClock.rounded(ProbeClock.continuousMs() - arrival),
        ], at: arrival)
        return pending
    }

    private func endPaste(_ pending: PendingPaste) {
        let lengthAfter = textStorage?.length ?? 0
        log?.record("pasteEnd", [
            "action": pending.action,
            "target": targetName,
            "insertedLength": lengthAfter - (pending.lengthBefore - pending.selectedLength),
            "lengthAfter": lengthAfter,
        ])
        if clearsAfterPaste { string = "" }
    }
}
