import Foundation
import IOKit.ps
import AjarShared

struct PowerSnapshot: Equatable {
    /// nil on Macs without a battery.
    let batteryPercent: Int?
    let onACPower: Bool
    let batteryTemperature: Double?
}

enum PowerMonitor {
    static func snapshot() -> PowerSnapshot {
        let temperature = BatterySensor.temperatureCelsius()
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return PowerSnapshot(batteryPercent: nil, onACPower: true, batteryTemperature: temperature)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onAC = providing == kIOPSACPowerValue
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return PowerSnapshot(batteryPercent: current * 100 / max, onACPower: onAC, batteryTemperature: temperature)
        }
        return PowerSnapshot(batteryPercent: nil, onACPower: onAC, batteryTemperature: temperature)
    }
}
