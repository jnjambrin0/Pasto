import Foundation
import os

/// Typed settings on top of `UserDefaults`.
///
/// Only values the user changed are persisted; everything else resolves to the key's default, so
/// a default can change in a later version without migrating anything.
public final class ConfigStore: Sendable {
    /// `UserDefaults` is documented as thread-safe, but the SDK does not declare it `Sendable`.
    private nonisolated(unsafe) let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The stored value, or the key's default when nothing is stored or it cannot be decoded.
    public func value<V>(for key: ConfigKey<V>) -> V {
        guard let stored = defaults.object(forKey: key.name),
              let value = V(storedRepresentation: stored)
        else { return key.defaultValue }
        return value
    }

    public func set<V>(_ value: V, for key: ConfigKey<V>) {
        defaults.set(value.storedRepresentation, forKey: key.name)
    }

    /// Forgets the stored value, so the key resolves to its default again.
    public func reset<V>(_ key: ConfigKey<V>) {
        defaults.removeObject(forKey: key.name)
    }

    public func isSet<V>(_ key: ConfigKey<V>) -> Bool {
        defaults.object(forKey: key.name) != nil
    }

    /// Emits the current value and then every change, skipping consecutive duplicates. Changes
    /// made by another process (`defaults write`, say) arrive too, for a key whose name has no
    /// dot: the observation goes by key path, in which a dot separates keys.
    public func values<V>(for key: ConfigKey<V>) -> AsyncStream<V> {
        AsyncStream { continuation in
            let lastEmitted = OSAllocatedUnfairLock<V?>(initialState: nil)
            // Reading and emitting under one lock keeps the stream in the order the changes happened,
            // whichever threads they come from.
            let emitIfChanged: @Sendable () -> Void = { [self] in
                lastEmitted.withLock { last in
                    let current = value(for: key)
                    guard current != last else { return }
                    last = current
                    continuation.yield(current)
                }
            }

            // `UserDefaults` posts this for any key, synchronously on the thread that made the
            // change, but only for changes made in this process.
            // The token only ever goes back to `NotificationCenter`, which is thread-safe.
            nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: defaults, queue: nil
            ) { _ in emitIfChanged() }
            let keyObserver = DefaultsKeyObserver(defaults: defaults, keyPath: key.name, onChange: emitIfChanged)
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
                keyObserver?.invalidate()
            }

            // Observing before the first emission leaves no window in which a change could be missed.
            emitIfChanged()
        }
    }
}

/// Key-value observation of one key of a `UserDefaults`, which reports changes made by other
/// processes as well.
private final class DefaultsKeyObserver: NSObject, @unchecked Sendable {
    // Set once in `init` and only read afterwards; `invalidate` runs once.
    private let defaults: UserDefaults
    private let keyPath: String
    private let onChange: @Sendable () -> Void

    /// Nil for a key whose name is no key path (it has a dot in it).
    init?(defaults: UserDefaults, keyPath: String, onChange: @escaping @Sendable () -> Void) {
        guard !keyPath.contains(".") else { return nil }
        self.defaults = defaults
        self.keyPath = keyPath
        self.onChange = onChange
        super.init()
        defaults.addObserver(self, forKeyPath: keyPath, options: [], context: nil)
    }

    func invalidate() {
        defaults.removeObserver(self, forKeyPath: keyPath)
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        onChange()
    }
}
