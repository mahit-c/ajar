import AppKit
import Foundation
import ServiceManagement
import UserNotifications
import AjarShared

@MainActor
final class SessionController: ObservableObject {
    static let shared = SessionController()

    enum HelperState: Equatable {
        case unknown, notInstalled, needsApproval
        case installed(version: String)
    }

    @Published private(set) var isActive = false
    @Published private(set) var endsAt: Date?
    @Published private(set) var systemSleepDisabled = false
    @Published private(set) var helperState: HelperState = .unknown
    @Published private(set) var lastStopReason: String?
    @Published private(set) var lastError: String?
    @Published private(set) var power = PowerMonitor.snapshot()
    @Published private(set) var now = Date()
    /// Duration picked in the Settings window; 0 means indefinitely.
    @Published var settingsDuration: TimeInterval = 0
    /// Last Settings tab shown, so the window reopens where the user left it.
    @Published var settingsTab: String { didSet { defaults.set(settingsTab, forKey: Keys.settingsTab) } }

    @Published var stopBelowBattery: Bool { didSet { defaults.set(stopBelowBattery, forKey: Keys.stopBelowBattery) } }
    @Published var batteryThreshold: Int { didSet { defaults.set(batteryThreshold, forKey: Keys.batteryThreshold) } }
    @Published var stopWhenUnplugged: Bool { didSet { defaults.set(stopWhenUnplugged, forKey: Keys.stopWhenUnplugged) } }
    @Published var thermalProtection: Bool { didSet { defaults.set(thermalProtection, forKey: Keys.thermalProtection) } }
    @Published var temperatureLimitEnabled: Bool { didSet { defaults.set(temperatureLimitEnabled, forKey: Keys.temperatureLimitEnabled) } }
    @Published var temperatureLimit: Int { didSet { defaults.set(temperatureLimit, forKey: Keys.temperatureLimit) } }
    @Published var temperatureWarning: Bool { didSet { defaults.set(temperatureWarning, forKey: Keys.temperatureWarning) } }
    @Published var lockOnLidClose: Bool { didSet { defaults.set(lockOnLidClose, forKey: Keys.lockOnLidClose) } }

    static let temperatureLimits = [40, 45, 50]
    static let warningMargin = 5

    private enum Keys {
        static let stopBelowBattery = "stopBelowBattery"
        static let batteryThreshold = "batteryThreshold"
        static let stopWhenUnplugged = "stopWhenUnplugged"
        static let thermalProtection = "thermalProtection"
        static let temperatureLimitEnabled = "temperatureLimitEnabled"
        static let temperatureLimit = "temperatureLimit"
        static let temperatureWarning = "temperatureWarning"
        static let lockOnLidClose = "lockOnLidClose"
        static let settingsTab = "settingsTab"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let defaults = UserDefaults.standard
    private let helper = HelperClient()
    private var tickTimer: Timer?
    private var warnedAboutHeat = false
    private var lidTimer: Timer?
    private var lidWasClosed = false

    private init() {
        defaults.register(defaults: [
            Keys.stopBelowBattery: true,
            Keys.batteryThreshold: 20,
            Keys.stopWhenUnplugged: false,
            Keys.thermalProtection: true,
            Keys.temperatureLimitEnabled: true,
            Keys.temperatureLimit: 45,
            Keys.temperatureWarning: true,
            Keys.lockOnLidClose: true,
            Keys.settingsTab: "general",
        ])
        stopBelowBattery = defaults.bool(forKey: Keys.stopBelowBattery)
        batteryThreshold = defaults.integer(forKey: Keys.batteryThreshold)
        stopWhenUnplugged = defaults.bool(forKey: Keys.stopWhenUnplugged)
        thermalProtection = defaults.bool(forKey: Keys.thermalProtection)
        temperatureLimitEnabled = defaults.bool(forKey: Keys.temperatureLimitEnabled)
        temperatureLimit = defaults.integer(forKey: Keys.temperatureLimit)
        temperatureWarning = defaults.bool(forKey: Keys.temperatureWarning)
        lockOnLidClose = defaults.bool(forKey: Keys.lockOnLidClose)
        settingsTab = defaults.string(forKey: Keys.settingsTab) ?? "general"
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Keys.hasCompletedOnboarding) }
        set { defaults.set(newValue, forKey: Keys.hasCompletedOnboarding) }
    }

    // MARK: Lifecycle

    func launch() {
        helper.onInterruption = { [weak self] in self?.helperInterrupted() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.checkSafety() }
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        refresh()
    }

    func stopBeforeQuit() {
        guard isActive else { return }
        helper.disableSynchronously()
    }

    // MARK: Sessions

    func start(for duration: TimeInterval?) {
        guard case .installed = helperState else {
            installHelper { [weak self] ok in if ok { self?.start(for: duration) } }
            return
        }
        lastError = nil
        let snapshot = PowerMonitor.snapshot()
        if stopBelowBattery, !snapshot.onACPower, let percent = snapshot.batteryPercent, percent <= batteryThreshold {
            lastError = "Battery is at \(percent)%, below your \(batteryThreshold)% safety limit."
            return
        }
        if stopWhenUnplugged, !snapshot.onACPower {
            lastError = "Not plugged in, and “Stop When Unplugged” is on."
            return
        }
        if temperatureLimitEnabled, let celsius = snapshot.batteryTemperature, celsius >= Double(temperatureLimit) {
            lastError = "Battery is at \(Int(celsius))°C, above your \(temperatureLimit)°C limit."
            return
        }
        warnedAboutHeat = false
        helper.setSleepDisabled(true) { [weak self] error in
            guard let self else { return }
            if let error {
                lastError = error
                refresh()
                return
            }
            isActive = true
            endsAt = duration.map { Date().addingTimeInterval($0) }
            lastStopReason = nil
            systemSleepDisabled = true
            startWatchingLid()
        }
    }

    func stop(reason: String, notify: Bool = false) {
        isActive = false
        lidTimer?.invalidate()
        lidTimer = nil
        endsAt = nil
        lastStopReason = reason
        helper.setSleepDisabled(false) { [weak self] error in
            if let error { self?.lastError = "Couldn't restore sleep: \(error)" }
            self?.refresh()
        }
        if notify { postNotification(title: "Ajar stopped", body: "\(reason). Your Mac will sleep normally again.") }
    }

    // MARK: Lid lock

    /// Normally closing the lid sleeps the Mac, which locks it. Ajar keeps it awake, so it
    /// locks the screen itself on close: everything keeps running behind the lock screen.
    private func startWatchingLid() {
        lidWasClosed = LidMonitor.isClosed
        lidTimer?.invalidate()
        lidTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkLid() }
        }
    }

    private func checkLid() {
        let closed = LidMonitor.isClosed
        defer { lidWasClosed = closed }
        guard closed, !lidWasClosed, lockOnLidClose else { return }
        // Give macOS a moment to switch displays, then skip locking in clamshell mode
        // (lid closed with an external display in use).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, isActive, LidMonitor.isClosed, !LidMonitor.hasActiveDisplay else { return }
            ScreenLocker.lockNow()
        }
    }

    private func tick() {
        now = Date()
        power = PowerMonitor.snapshot()
        if isActive {
            if let endsAt, now >= endsAt {
                stop(reason: "Timer finished", notify: true)
                return
            }
            helper.heartbeat()
            checkSafety()
        }
        refresh()
    }

    private func checkSafety() {
        guard isActive else { return }
        let snapshot = PowerMonitor.snapshot()
        power = snapshot
        if thermalProtection, ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue {
            stop(reason: "Your Mac is running hot", notify: true)
        } else if temperatureLimitEnabled, let celsius = snapshot.batteryTemperature, celsius >= Double(temperatureLimit) {
            stop(reason: "Battery reached \(Int(celsius))°C", notify: true)
        } else if stopWhenUnplugged, !snapshot.onACPower {
            stop(reason: "Power adapter unplugged", notify: true)
        } else if stopBelowBattery, !snapshot.onACPower, let percent = snapshot.batteryPercent, percent <= batteryThreshold {
            stop(reason: "Battery dropped to \(percent)%", notify: true)
        } else if temperatureLimitEnabled, let celsius = snapshot.batteryTemperature {
            checkHeatWarning(celsius)
        }
    }

    /// Warns once as the battery approaches the limit, re-arming only after it has cooled
    /// well below the warning point so a temperature hovering at the line doesn't spam.
    private func checkHeatWarning(_ celsius: Double) {
        let warnAt = Double(temperatureLimit - Self.warningMargin)
        if celsius < warnAt - 3 {
            warnedAboutHeat = false
        } else if temperatureWarning, !warnedAboutHeat, celsius >= warnAt {
            warnedAboutHeat = true
            postNotification(
                title: "Your Mac is warming up",
                body: "Battery at \(Int(celsius))°C. Ajar will stop at \(temperatureLimit)°C. If it's in a bag, take it out."
            )
        }
    }

    /// Reads the real system state rather than trusting what we last asked for, and
    /// self-heals if a session we think is running was dropped (helper restart, power change).
    func refresh() {
        helper.status { [weak self] status in
            guard let self else { return }
            guard let status else {
                helperState = HelperInstaller.needsApproval ? .needsApproval : .notInstalled
                if isActive { lastError = "Lost contact with the Ajar helper." }
                return
            }
            helperState = .installed(version: status.version)
            systemSleepDisabled = status.sleepDisabled
            if isActive, !status.sleepDisabled || !status.sessionActive { reapply() }
        }
    }

    private func helperInterrupted() {
        if isActive { reapply() }
    }

    private func reapply() {
        helper.setSleepDisabled(true) { [weak self] error in
            guard let self else { return }
            if let error { lastError = "Couldn't re-apply: \(error)" } else { systemSleepDisabled = true; lastError = nil }
        }
    }

    // MARK: Helper management

    func installHelper(then completion: ((Bool) -> Void)? = nil) {
        lastError = nil
        do {
            try HelperInstaller.install()
        } catch {
            lastError = error.localizedDescription
            completion?(false)
            return
        }
        waitForHelper(attempts: 10, completion: completion)
    }

    /// launchd can take a moment to bring a freshly installed daemon up, so poll briefly.
    private func waitForHelper(attempts: Int, completion: ((Bool) -> Void)?) {
        helper.status { [weak self] status in
            guard let self else { return }
            if let status {
                helperState = .installed(version: status.version)
                systemSleepDisabled = status.sleepDisabled
                completion?(true)
            } else if attempts > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.waitForHelper(attempts: attempts - 1, completion: completion)
                }
            } else {
                let needsApproval = HelperInstaller.needsApproval
                helperState = needsApproval ? .needsApproval : .notInstalled
                lastError = needsApproval
                    ? "Approve Ajar in System Settings → General → Login Items, then try again."
                    : "The helper was installed but isn't responding. Use Copy Diagnostics and send it over."
                completion?(false)
            }
        }
    }

    func uninstallHelper() {
        let alert = NSAlert()
        alert.messageText = "Uninstall the Ajar helper?"
        alert.informativeText = "Closed-lid mode will stop working until you install it again. Normal sleep will be restored."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if isActive { stop(reason: "Helper uninstalled") }
        do {
            try HelperInstaller.uninstall()
        } catch {
            lastError = error.localizedDescription
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refresh() }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Launch at login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    // MARK: Display

    var statusLine: String {
        guard isActive else {
            return systemSleepDisabled ? "Off — but sleep is disabled system-wide" : "Off — Mac sleeps normally"
        }
        let temperature = power.batteryTemperature.map { " · \(Int($0.rounded()))°C" } ?? ""
        guard let endsAt else { return "On — staying awake, lid open or closed\(temperature)" }
        return "On — \(Self.formatRemaining(endsAt.timeIntervalSince(now))) left\(temperature)"
    }

    var thermalStateName: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }

    var temperatureDescription: String {
        power.batteryTemperature.map { String(format: "%.1f°C", $0) } ?? "Not available"
    }

    var helperDescription: String {
        switch helperState {
        case .unknown: return "Checking…"
        case .notInstalled: return "Not installed"
        case .needsApproval: return "Waiting for approval"
        case .installed(let version): return "Installed (v\(version))"
        }
    }

    static func formatRemaining(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int(interval.rounded(.up) / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(max(minutes, 1))m"
    }

    func copyDiagnostics() {
        let report = """
        Ajar \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Session active: \(isActive)\(endsAt.map { ", ends \($0)" } ?? "")
        Helper: \(helperDescription) via \(HelperInstaller.usesServiceManagement ? "SMAppService" : "legacy LaunchDaemon")
        Signing team: \(HelperInstaller.signingTeamID ?? "none (ad-hoc)")
        Thermal state: \(thermalStateName)
        Battery temperature: \(temperatureDescription) (limit \(temperatureLimitEnabled ? "\(temperatureLimit)°C" : "off"), helper backstop \(Int(AjarConstants.hardTemperatureLimit))°C)
        Power: \(power.onACPower ? "AC" : "battery")\(power.batteryPercent.map { ", \($0)%" } ?? "")
        Last stop reason: \(lastStopReason ?? "-")
        Last error: \(lastError ?? "-")

        $ pmset -g
        \(Self.shell("/usr/bin/pmset", ["-g"]))
        $ pmset -g assertions
        \(Self.shell("/usr/bin/pmset", ["-g", "assertions"]))
        """
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    private static func shell(_ path: String, _ args: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return "(failed to run)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
