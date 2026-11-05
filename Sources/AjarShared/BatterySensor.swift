import Foundation
import IOKit
import IOKit.ps

public enum BatterySensor {
    /// Battery temperature in °C from the AppleSmartBattery registry entry (no root needed).
    /// nil on Macs without a battery or if the reading looks implausible.
    public static func temperatureCelsius() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let raw = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Int else { return nil }
        let celsius = Double(raw) / 100
        return (0...100).contains(celsius) ? celsius : nil
    }

    /// Internal battery charge (nil without a battery) and whether the Mac runs on AC power.
    public static func charge() -> (percent: Int?, onACPower: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return (nil, true)
        }
        let onAC = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPSACPowerValue
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return (current * 100 / max, onAC)
        }
        return (nil, onAC)
    }
}
