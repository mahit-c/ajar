import Foundation
import AjarShared

struct PowerSnapshot: Equatable {
    /// nil on Macs without a battery.
    let batteryPercent: Int?
    let onACPower: Bool
    let batteryTemperature: Double?
}

enum PowerMonitor {
    static func snapshot() -> PowerSnapshot {
        let charge = BatterySensor.charge()
        return PowerSnapshot(
            batteryPercent: charge.percent,
            onACPower: charge.onACPower,
            batteryTemperature: BatterySensor.temperatureCelsius()
        )
    }
}
