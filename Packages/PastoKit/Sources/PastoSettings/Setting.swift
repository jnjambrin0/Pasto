import PastoFoundation
import SwiftUI

/// One setting as SwiftUI state: reading tracks it, writing stores it at once, and a change made
/// elsewhere (another part of the app, `defaults write`) shows up here too.
@Observable
final class Setting<Value: ConfigValue> {
    private let config: ConfigStore
    private let key: ConfigKey<Value>
    private var current: Value
    @ObservationIgnored private var observation: Task<Void, Never>?

    init(_ key: ConfigKey<Value>, in config: ConfigStore) {
        self.config = config
        self.key = key
        current = config.value(for: key)
        observation = Task { [weak self] in
            for await value in config.values(for: key) {
                guard let self else { return }
                if current != value { current = value }
            }
        }
    }

    isolated deinit {
        observation?.cancel()
    }

    var value: Value {
        get { current }
        set {
            current = newValue
            config.set(newValue, for: key)
        }
    }

    var binding: Binding<Value> {
        Binding(get: { self.value }, set: { self.value = $0 })
    }
}
