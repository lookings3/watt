import Foundation
import IOKit
import CSMC

struct BatterySnapshot {
    var percent: Int
    var isCharging: Bool
    var isExternal: Bool
    var fullyCharged: Bool
    var minutesRemaining: Int?
    var watts: Double          // positive: charging, negative: discharging
    var temperature: Double?
    var cycleCount: Int
    var designCycles: Int
    var healthPercent: Double?
    var volts: Double = 0
    var amps: Double = 0            // positive: charging, negative: discharging
    var systemLoad: Double?         // Mac power draw (W)
    var inputWatts: Double?         // power coming from the charger (W)
    var adapterWatts: Int?          // charger rated output (W)

    var statusText: String {
        if isCharging { return L("충전 중", "Charging") }
        if isExternal { return fullyCharged ? L("전원 연결 · 완충", "Plugged in · Fully charged") : L("전원 연결 · 충전 안 함", "Plugged in · Not charging") }
        return L("배터리 사용", "On battery")
    }
    var timeText: String {
        if isExternal && !isCharging { return "" }
        guard let m = minutesRemaining else { return L("계산 중", "Calculating") }
        let t = m >= 60 ? L("\(m / 60)시간 \(m % 60)분", "\(m / 60)h \(m % 60)m") : L("\(m)분", "\(m)m")
        return isCharging ? L("완충까지 \(t)", "\(t) until full") : L("\(t) 남음", "\(t) left")
    }
}

struct PowerFlow {
    static let idle = 0.3
    var toMacFromAdapter: Double
    var toBatteryFromAdapter: Double
    var toMacFromBattery: Double
    var macWatts: Double { toMacFromAdapter + toMacFromBattery }
}

extension BatterySnapshot {
    /// A Mac running on battery can't draw 0 W. A zero means macOS hasn't refreshed the value yet.
    var isMeasuring: Bool { !isExternal && abs(watts) < PowerFlow.idle }

    var flow: PowerFlow {
        func clean(_ w: Double) -> Double { w < PowerFlow.idle ? 0 : w }
        let charging = max(watts, 0), draining = max(-watts, 0)
        guard isExternal else {
            return PowerFlow(toMacFromAdapter: 0, toBatteryFromAdapter: 0, toMacFromBattery: clean(draining))
        }
        let load = systemLoad ?? max((inputWatts ?? 0) - charging, 0)
        return PowerFlow(toMacFromAdapter: clean(max(load - draining, 0)),
                         toBatteryFromAdapter: clean(charging), toMacFromBattery: clean(draining))
    }

    var flowText: String {
        let f = flow
        if isMeasuring { return L("전력을 측정하고 있어요. 1분 안에 값이 표시돼요", "Measuring power. A value will appear within a minute") }
        if !isExternal { return L("배터리로 동작하고 있어요", "Running on battery") }
        if f.toMacFromBattery > 0 {
            return String(format: L("전원이 연결돼 있지만 충전기 출력이 모자라 배터리가 %.1f W를 보태고 있어요", "Plugged in, but the charger falls short. The battery is adding %.1f W"), f.toMacFromBattery)
        }
        if f.toBatteryFromAdapter > 0 { return String(format: L("충전기가 배터리에 %.1f W를 채우고 있어요", "The charger is adding %.1f W to the battery"), f.toBatteryFromAdapter) }
        return L("충전기 전력으로 동작하고 배터리는 쉬고 있어요", "Running on the charger. The battery is resting")
    }
}

enum Battery {
    private static func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }

    static func read() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any],
              let percent = int(d["CurrentCapacity"]) else { return nil }

        let data = d["BatteryData"] as? [String: Any] ?? [:]
        let charging = d["IsCharging"] as? Bool ?? false
        let external = d["ExternalConnected"] as? Bool ?? false
        let rawTime = int(charging ? d["AvgTimeToFull"] : d["TimeRemaining"])
        let validTime = rawTime.flatMap { $0 > 0 && $0 < 100 * 60 ? $0 : nil } // values of 100 hours or more mean not calculated yet
        let mV = Double(int(d["Voltage"]) ?? 0)
        let mA = Double(int(d["InstantAmperage"]) ?? 0)
        var health: Double?
        if let maxCap = int(data["AppleRawMaxCapacity"]), let design = int(data["DesignCapacity"]), design > 0 {
            health = Double(maxCap) / Double(design) * 100
        }
        let t = smc_battery_temperature()
        let telemetry = d["PowerTelemetryData"] as? [String: Any] ?? [:]
        let adapter = d["AdapterDetails"] as? [String: Any] ?? [:]
        func milliwatts(_ key: String) -> Double? { int(telemetry[key]).flatMap { $0 > 0 ? Double($0) / 1000 : nil } }
        return BatterySnapshot(
            percent: percent, isCharging: charging, isExternal: external,
            fullyCharged: d["FullyCharged"] as? Bool ?? false,
            minutesRemaining: validTime, watts: mV * mA / 1_000_000,
            temperature: t > 0 ? t : nil,
            cycleCount: int(d["CycleCount"]) ?? 0,
            designCycles: int(d["DesignCycleCount9C"]) ?? 1000,
            healthPercent: health, volts: mV / 1000, amps: mA / 1000,
            systemLoad: milliwatts("SystemLoad"),
            inputWatts: external ? milliwatts("SystemPowerIn") : nil,
            adapterWatts: external ? int(adapter["Watts"]) : nil)
    }
}
