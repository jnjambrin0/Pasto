import Foundation
import IOKit.ps

/// The Mac's own conditions: Low Power Mode, thermal state and battery.
public struct SystemDeviceConditions: DeviceConditions {
    /// On battery and at or below this charge, background work waits.
    static let lowBatteryFraction = 0.2

    public init() {}

    public var isConstrained: Bool {
        let process = ProcessInfo.processInfo
        return Self.isConstrained(
            lowPowerMode: process.isLowPowerModeEnabled,
            thermalState: process.thermalState,
            batteryFraction: Self.batteryFractionOnBattery()
        )
    }

    /// - Parameter batteryFraction: The charge left when the Mac runs on battery; `nil` on power
    ///   or without a battery.
    static func isConstrained(lowPowerMode: Bool, thermalState: ProcessInfo.ThermalState, batteryFraction: Double?) -> Bool {
        if lowPowerMode { return true }
        if thermalState == .serious || thermalState == .critical { return true }
        if let batteryFraction, batteryFraction <= lowBatteryFraction { return true }
        return false
    }

    /// The lowest charge among the batteries the Mac is running on, or `nil` when it is not
    /// running on one.
    private static func batteryFractionOnBattery() -> Double? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        let fractions = sources.compactMap { source -> Double? in
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { return nil }
            return Double(current) / Double(maximum)
        }
        return fractions.min()
    }
}
