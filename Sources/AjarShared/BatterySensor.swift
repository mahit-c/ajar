import Foundation
import IOKit

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
}
