import AppKit

/// Which application the user is in, as it changes.
enum FrontmostApplication {
    /// The bundle identifier of the application in front now, and then of every application
    /// that becomes active.
    static func bundleIdentifiers() -> AsyncStream<String?> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let activations = NSWorkspace.shared.notificationCenter
                    .notifications(named: NSWorkspace.didActivateApplicationNotification)
                    .map { ($0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier }
                continuation.yield(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
                for await bundleIdentifier in activations {
                    continuation.yield(bundleIdentifier)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
