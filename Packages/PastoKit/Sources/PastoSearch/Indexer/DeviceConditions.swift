/// Whether the Mac can spare background work right now.
public protocol DeviceConditions: Sendable {
    /// Low Power Mode is on, the Mac is hot, or it runs on a battery that is nearly empty.
    var isConstrained: Bool { get }
}
