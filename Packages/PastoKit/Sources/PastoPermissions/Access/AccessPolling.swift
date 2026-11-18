/// Turns a question the system has no notification for into a stream of its answers.
enum AccessPolling {
    /// Emits the answer now, and again whenever asking at every interval gives a different one.
    static func states<Value: Equatable & Sendable>(
        every interval: Duration,
        probe: @escaping @MainActor () -> Value
    ) -> AsyncStream<Value> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                var last: Value?
                while !Task.isCancelled {
                    let current = probe()
                    if current != last {
                        last = current
                        continuation.yield(current)
                    }
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
