/// Brings a task back to the main actor after awaiting an injected async closure.
///
/// A closure value typed `(…) async -> Void` is called as if it stayed on the caller's actor
/// (`NonisolatedNonsendingByDefault`), but one that awaits something concurrent inside — the
/// default `Task.sleep` — can hand control back on the cooperative pool. Code that goes on to
/// touch main-actor state would then run off the main thread and trap. Awaiting this, an
/// isolated async function, makes the hop explicit.
public enum MainActorReturn {
    @MainActor
    public static func ensure() async {
        MainActor.preconditionIsolated()
    }
}
