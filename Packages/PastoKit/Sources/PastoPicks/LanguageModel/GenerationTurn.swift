import Foundation

/// Lets one language model request run at a time; the others wait in the order they came, and
/// one that is cancelled while waiting leaves the line.
actor GenerationTurn {
    private var isTaken = false
    private var waiting: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    /// Returns once it is the caller's turn, which it must then `release()`.
    func take() async throws {
        guard isTaken else {
            isTaken = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Cancelled before getting in line: the handler below may already have run.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                waiting.append((id, continuation))
            }
        } onCancel: {
            Task { await self.leave(id) }
        }
    }

    /// The turn goes straight to the first in line, if there is one.
    func release() {
        guard !waiting.isEmpty else {
            isTaken = false
            return
        }
        waiting.removeFirst().continuation.resume()
    }

    private func leave(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
