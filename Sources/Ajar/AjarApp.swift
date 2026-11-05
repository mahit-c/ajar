import AppKit
import ServiceManagement
import SwiftUI

@main
struct AjarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var session = SessionController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(session)
        } label: {
            Image(systemName: session.isActive ? "sun.max.fill" : "moon.zzz")
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            SessionController.shared.launch()
            if !SessionController.shared.hasCompletedOnboarding { WindowManager.shared.showWelcome() }
        }
    }

    /// Opening Ajar again (Finder, Spotlight, Raycast) while it's running shows Settings,
    /// so it's reachable even when the menu bar icon is hidden behind the notch.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { WindowManager.shared.showSettings() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { SessionController.shared.stopBeforeQuit() }
    }
}

struct MenuContent: View {
    @EnvironmentObject private var session: SessionController

    private static let durations: [(String, TimeInterval)] = [
        ("15 Minutes", 15 * 60), ("30 Minutes", 30 * 60), ("1 Hour", 3600),
        ("2 Hours", 2 * 3600), ("4 Hours", 4 * 3600), ("8 Hours", 8 * 3600),
    ]

    var body: some View {
        Text(session.statusLine)
        if let error = session.lastError {
            Text("⚠︎ \(error)")
        } else if !session.isActive, let reason = session.lastStopReason {
            Text("Last stopped: \(reason)")
        }

        Divider()

        if session.helperState == .needsApproval {
            Button("Approve Helper in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
        }
        if session.isActive {
            Button("Stop — Let Mac Sleep") { session.stop(reason: "Stopped manually") }
        } else {
            Button("Keep Awake Indefinitely") { session.start(for: nil) }
            Menu("Keep Awake For") {
                ForEach(Self.durations, id: \.1) { label, seconds in
                    Button(label) { session.start(for: seconds) }
                }
            }
        }

        Divider()

        Menu("Safety") {
            Toggle("Stop at Low Battery", isOn: $session.stopBelowBattery)
            Picker("Low Battery Level", selection: $session.batteryThreshold) {
                ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)%").tag($0) }
            }
            Toggle("Lock Screen When Lid Closes", isOn: $session.lockOnLidClose)
            Divider()
            Toggle("Stop When Unplugged", isOn: $session.stopWhenUnplugged)
            Toggle("Stop When Mac Runs Hot", isOn: $session.thermalProtection)
            Divider()
            Toggle("Stop When Battery Is Hot", isOn: $session.temperatureLimitEnabled)
            Picker("Temperature Limit", selection: $session.temperatureLimit) {
                ForEach(SessionController.temperatureLimits, id: \.self) { Text("\($0)°C").tag($0) }
            }
        }

        Menu("Diagnostics") {
            Text("System sleep disabled: \(session.systemSleepDisabled ? "Yes" : "No")")
            Text("Helper: \(session.helperDescription)")
            Text("Battery temperature: \(session.temperatureDescription)")
            Text("Thermal state: \(session.thermalStateName)")
            if let percent = session.power.batteryPercent {
                Text("Battery: \(percent)% \(session.power.onACPower ? "(on power)" : "(on battery)")")
            }
            Button("Copy Diagnostics") { session.copyDiagnostics() }
            Divider()
            Button("Reinstall Helper…") { session.installHelper() }
            Button("Uninstall Helper…") { session.uninstallHelper() }
        }

        Toggle("Launch at Login", isOn: Binding(
            get: { session.launchAtLogin },
            set: { session.launchAtLogin = $0 }
        ))

        Divider()

        Button("Settings…") { WindowManager.shared.showSettings() }
            .keyboardShortcut(",")
        Button("Quit Ajar") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
