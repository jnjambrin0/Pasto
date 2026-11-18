import Carbon.HIToolbox
import Foundation
import os
import PastoFoundation

/// Registers system-wide hot keys with Carbon's `RegisterEventHotKey`.
///
/// Carbon hot keys are consumed by the system before they reach the frontmost application and
/// need no Accessibility permission, unlike event taps. Each caller owns at most one hot key:
/// registering another shortcut for the same caller replaces the previous one, but only once
/// the new one is in place, so there is never a moment without a hot key.
@MainActor
public final class HotKeyCenter {
    private struct Combination: Hashable {
        let keyCode: UInt32
        let modifiers: UInt32
    }

    private struct HotKey {
        let caller: String
        let identifier: UInt32
        var action: @MainActor () -> Void
        /// Nil while paused: the entry is kept but not registered with Carbon.
        var reference: EventHotKeyRef?
    }

    private var hotKeys: [Combination: HotKey] = [:]
    private var pauseCount = 0
    private var eventHandler: EventHandlerRef?
    private let reference = WeakReference()
    private let log = Log.logger(.shortcut)

    public init() {
        reference.center = self
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            handleHotKeyEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(reference).toOpaque(),
            &eventHandler
        )
        if status != noErr {
            // Not fatal: registrations still go ahead, they just never fire.
            log.error("Could not install the hot key handler: \(status)")
        }
    }

    isolated deinit {
        for hotKey in hotKeys.values {
            if let reference = hotKey.reference { UnregisterEventHotKey(reference) }
        }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    /// Makes `shortcut` the hot key of `caller`. Failures are logged and otherwise silent: the
    /// setting keeps its value and the previous hot key, if any, stays active. A key code no key
    /// can have is one of those failures, not a crash.
    public func register(_ shortcut: Shortcut, caller: String, action: @escaping @MainActor () -> Void) {
        guard let keyCode = UInt32(exactly: shortcut.keyCode) else {
            log.error("Hot key refused for \(caller, privacy: .public): key code out of range (\(shortcut.keyCode))")
            return
        }
        let combination = Combination(keyCode: keyCode, modifiers: shortcut.carbonModifiers)

        if let existing = hotKeys[combination] {
            if existing.caller == caller {
                hotKeys[combination]?.action = action
            } else {
                log.error("Hot key refused for \(caller, privacy: .public): held by \(existing.caller, privacy: .public)")
            }
            return
        }

        var hotKey = HotKey(caller: caller, identifier: HotKeyIdentifiers.next(), action: action, reference: nil)
        let status = registerWithCarbon(&hotKey, combination)
        guard status == noErr else {
            log.error("Hot key registration failed for \(caller, privacy: .public): \(status)")
            return
        }
        if pauseCount > 0 {
            unregisterFromCarbon(&hotKey)
        }
        if let previous = hotKeys.first(where: { $0.value.caller == caller }) {
            remove(previous.key)
        }
        hotKeys[combination] = hotKey
    }

    /// Whether `shortcut` is free to be a hot key: asks Carbon for it exclusively and gives it
    /// back at once. Another app holding the combination makes the request fail. Registrations
    /// made with `register` stay as they are (they never ask for exclusivity), and a combination
    /// this center already holds counts as available.
    public func isAvailable(_ shortcut: Shortcut) -> Bool {
        guard let keyCode = UInt32(exactly: shortcut.keyCode) else { return false }
        let combination = Combination(keyCode: keyCode, modifiers: shortcut.carbonModifiers)
        if hotKeys[combination] != nil { return true }

        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            combination.keyCode,
            combination.modifiers,
            EventHotKeyID(signature: 1, id: HotKeyIdentifiers.next()),
            GetEventDispatcherTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )
        guard status == noErr else {
            log.info("Hot key \(shortcut.keyCode, privacy: .public)/\(shortcut.internalModifiers, privacy: .public) is not available: \(status)")
            return false
        }
        if let reference { UnregisterEventHotKey(reference) }
        return true
    }

    public func unregister(caller: String) {
        if let entry = hotKeys.first(where: { $0.value.caller == caller }) {
            remove(entry.key)
        }
    }

    /// Releases every hot key in Carbon while keeping the registrations, so that the shortcut
    /// recorder can see the combinations. Calls nest; `resume()` undoes one `pause()`.
    public func pause() {
        pauseCount += 1
        guard pauseCount == 1 else { return }
        for combination in hotKeys.keys {
            if var hotKey = hotKeys[combination] {
                unregisterFromCarbon(&hotKey)
                hotKeys[combination] = hotKey
            }
        }
    }

    public func resume() {
        guard pauseCount > 0 else { return }
        pauseCount -= 1
        guard pauseCount == 0 else { return }
        for combination in Array(hotKeys.keys) {
            guard var hotKey = hotKeys[combination] else { continue }
            if registerWithCarbon(&hotKey, combination) == noErr {
                hotKeys[combination] = hotKey
            } else {
                log.error("Hot key could not be restored for \(hotKey.caller, privacy: .public)")
                hotKeys[combination] = nil
            }
        }
    }

    fileprivate func fire(_ identifier: UInt32) {
        hotKeys.values.first { $0.identifier == identifier }?.action()
    }

    private func remove(_ combination: Combination) {
        guard var hotKey = hotKeys.removeValue(forKey: combination) else { return }
        unregisterFromCarbon(&hotKey)
    }

    private func registerWithCarbon(_ hotKey: inout HotKey, _ combination: Combination) -> OSStatus {
        RegisterEventHotKey(
            combination.keyCode,
            combination.modifiers,
            EventHotKeyID(signature: 1, id: hotKey.identifier),
            GetEventDispatcherTarget(),
            0,
            &hotKey.reference
        )
    }

    private func unregisterFromCarbon(_ hotKey: inout HotKey) {
        if let reference = hotKey.reference {
            UnregisterEventHotKey(reference)
            hotKey.reference = nil
        }
    }
}

/// Process-wide hot key identifiers, starting at 1. An identifier is consumed even when Carbon
/// then refuses the registration.
private enum HotKeyIdentifiers {
    private static let counter = OSAllocatedUnfairLock(initialState: UInt32(0))

    static func next() -> UInt32 {
        counter.withLock { value in
            value += 1
            return value
        }
    }
}

/// What the C callback receives: a box that outlives nothing and never dangles, because the
/// center it points to is only reachable through a weak reference.
private final class WeakReference: @unchecked Sendable {
    weak var center: HotKeyCenter?
}

/// The action runs on the next pass of the main run loop (in common modes, so also during
/// modal and tracking loops), never inside Carbon's call. The handler always reports success.
private func handleHotKeyEvent(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData, GetEventClass(event) == OSType(kEventClassKeyboard) else { return noErr }

    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    let identifier = hotKeyID.id
    let reference = Unmanaged<WeakReference>.fromOpaque(userData).takeUnretainedValue()
    RunLoop.main.perform(inModes: [.common]) {
        MainActor.assumeIsolated {
            reference.center?.fire(identifier)
        }
    }
    return noErr
}
