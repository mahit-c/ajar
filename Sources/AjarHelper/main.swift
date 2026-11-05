import Darwin
import Foundation
import IOKit.ps
import AjarShared

// Root LaunchDaemon. Owns the system-wide `pmset disablesleep` flag and guarantees it is
// switched back off whenever the app goes away, hangs, the Mac overheats, or a previous
// session was left behind by a crash or reboot.

func log(_ message: String) {
    NSLog("[ajar-helper] %@", message)
}

enum PMSet {
    /// Every call is bounded: a hung pmset must never wedge the session queue, because the
    /// watchdog that restores sleep runs on that same queue.
    @discardableResult
    static func run(_ args: [String], timeout: TimeInterval = 10) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do { try process.run() } catch { return (-1, error.localizedDescription) }

        var data = Data()
        let reader = DispatchGroup()
        reader.enter()
        DispatchQueue.global().async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            reader.leave()
        }

        if exited.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut { kill(process.processIdentifier, SIGKILL) }
            log("pmset \(args.joined(separator: " ")) timed out after \(Int(timeout))s")
            return (-1, "pmset timed out")
        }
        _ = reader.wait(timeout: .now() + 2)
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static var sleepDisabled: Bool {
        for line in run(["-g"]).output.split(separator: "\n") where line.contains("SleepDisabled") {
            return line.split(whereSeparator: \.isWhitespace).last == "1"
        }
        return false
    }

    /// Returns nil on success, otherwise an error message. Retries once, since restoring
    /// sleep is the one operation that must not silently fail.
    static func setSleepDisabled(_ disabled: Bool) -> String? {
        var error: String?
        for attempt in 1...2 {
            let result = run(["-a", "disablesleep", disabled ? "1" : "0"])
            if result.status != 0 {
                error = result.output.isEmpty ? "pmset exited with status \(result.status)" : result.output
            } else if sleepDisabled != disabled {
                error = "pmset ran but SleepDisabled did not change"
            } else {
                return nil
            }
            if attempt == 1 { log("setSleepDisabled(\(disabled)) failed, retrying: \(error ?? "")") }
        }
        return error
    }
}

final class Session {
    static let shared = Session()
    static let heartbeatTimeout: TimeInterval = 60

    private let queue = DispatchQueue(label: "io.github.mahit-c.ajar.helper.session")
    private var owner: NSXPCConnection?
    private var lastHeartbeat = Date()
    // Present only while Ajar has sleep disabled, so a crash or reboot mid-session can be
    // detected on the next launch without clobbering a setting the user made by hand.
    private let markerURL = URL(fileURLWithPath: "/Library/Application Support/Ajar/session-active")

    var isActive: Bool { queue.sync { owner != nil } }

    func recoverFromStaleSession() {
        queue.sync {
            guard FileManager.default.fileExists(atPath: markerURL.path) else { return }
            log("Found stale session marker; restoring normal sleep")
            _ = PMSet.setSleepDisabled(false)
            try? FileManager.default.removeItem(at: markerURL)
        }
    }

    func enable(for connection: NSXPCConnection) -> String? {
        queue.sync {
            if let error = PMSet.setSleepDisabled(true) { return error }
            owner = connection
            lastHeartbeat = Date()
            try? FileManager.default.createDirectory(at: markerURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: markerURL.path, contents: nil)
            log("Session started")
            return nil
        }
    }

    func disable(reason: String) -> String? {
        queue.sync { endLocked(reason) }
    }

    func heartbeat(from connection: NSXPCConnection) {
        queue.sync { if owner === connection { lastHeartbeat = Date() } }
    }

    func connectionClosed(_ connection: NSXPCConnection) {
        queue.sync { if owner === connection { _ = endLocked("app disconnected") } }
    }

    func checkWatchdog() {
        queue.sync {
            if owner != nil, Date().timeIntervalSince(lastHeartbeat) > Self.heartbeatTimeout {
                _ = endLocked("no heartbeat from app for \(Int(Self.heartbeatTimeout))s")
            }
        }
    }

    /// Backstops that apply whatever the user's settings in the app are.
    func checkSafety() {
        queue.sync {
            guard owner != nil else { return }
            let charge = BatterySensor.charge()
            if ProcessInfo.processInfo.thermalState == .critical {
                _ = endLocked("critical thermal state")
            } else if let celsius = BatterySensor.temperatureCelsius(), celsius >= AjarConstants.hardTemperatureLimit {
                _ = endLocked("battery at \(Int(celsius))°C")
            } else if !charge.onACPower, let percent = charge.percent, percent <= AjarConstants.hardBatteryFloor {
                _ = endLocked("battery at \(percent)%")
            }
        }
    }

    /// macOS can drop the override when the power source changes (the classic Amphetamine
    /// failure on Apple Silicon), so re-assert it on every change.
    func powerSourceChanged() {
        queue.sync {
            guard owner != nil else { return }
            log("Power source changed; re-applying disablesleep")
            if let error = PMSet.setSleepDisabled(true) { log("Re-apply failed: \(error)") }
        }
    }

    private func endLocked(_ reason: String) -> String? {
        let wasActive = owner != nil
        owner = nil
        try? FileManager.default.removeItem(at: markerURL)
        if wasActive { log("Session ended: \(reason)") }
        return PMSet.setSleepDisabled(false)
    }
}

final class HelperService: NSObject, AjarHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (Bool, String?) -> Void) {
        let error: String?
        if disabled {
            guard let connection = NSXPCConnection.current() else { return reply(false, "No XPC connection") }
            error = Session.shared.enable(for: connection)
        } else {
            error = Session.shared.disable(reason: "requested by app")
        }
        reply(error == nil, error)
    }

    func status(reply: @escaping (Bool, Bool, String) -> Void) {
        reply(PMSet.sleepDisabled, Session.shared.isActive, AjarConstants.helperVersion)
    }

    func heartbeat(reply: @escaping () -> Void) {
        if let connection = NSXPCConnection.current() { Session.shared.heartbeat(from: connection) }
        reply()
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(AjarConstants.clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: AjarHelperProtocol.self)
        connection.exportedObject = HelperService()
        let closed: () -> Void = { [weak connection] in
            if let connection { Session.shared.connectionClosed(connection) }
        }
        connection.invalidationHandler = closed
        connection.interruptionHandler = closed
        connection.resume()
        return true
    }
}

log("Starting v\(AjarConstants.helperVersion)")
Session.shared.recoverFromStaleSession()

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: AjarConstants.helperLabel)
listener.delegate = delegate
listener.resume()

let watchdog = Timer(timeInterval: 10, repeats: true) { _ in
    Session.shared.checkWatchdog()
    Session.shared.checkSafety()
}
RunLoop.main.add(watchdog, forMode: .default)

let powerCallback: IOPowerSourceCallbackType = { _ in Session.shared.powerSourceChanged() }
if let source = IOPSNotificationCreateRunLoopSource(powerCallback, nil)?.takeRetainedValue() {
    CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
}

let thermalObserver = NotificationCenter.default.addObserver(
    forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil
) { _ in Session.shared.checkSafety() }

RunLoop.main.run()
