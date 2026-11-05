import ServiceManagement
import SwiftUI
import AjarShared

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "laptopcomputer") }
            SafetyTab().tabItem { Label("Safety", systemImage: "thermometer.medium") }
            HelperTab().tabItem { Label("Helper", systemImage: "lock.shield") }
            AboutTab().tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 520, height: 400)
    }
}

private struct GeneralTab: View {
    @EnvironmentObject private var session: SessionController

    private static let durations: [(String, TimeInterval)] = [
        ("Indefinitely", 0), ("15 minutes", 15 * 60), ("30 minutes", 30 * 60), ("1 hour", 3600),
        ("2 hours", 2 * 3600), ("4 hours", 4 * 3600), ("8 hours", 8 * 3600),
    ]

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(systemName: session.isActive ? "sun.max.fill" : "moon.zzz")
                        .font(.system(size: 34))
                        .foregroundStyle(session.isActive ? Color.orange : Color.secondary)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.isActive ? "Staying awake" : "Sleeping normally").font(.title3.bold())
                        Text(session.statusLine).foregroundStyle(.secondary)
                        if let error = session.lastError {
                            Text(error).foregroundStyle(.red).font(.callout)
                        } else if !session.isActive, let reason = session.lastStopReason {
                            Text("Last stopped: \(reason)").foregroundStyle(.secondary).font(.callout)
                        }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { session.isActive },
                        set: { $0 ? session.start(for: session.settingsDuration > 0 ? session.settingsDuration : nil) : session.stop(reason: "Stopped manually") }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.large)
                    .labelsHidden()
                }
                .padding(.vertical, 6)

                Picker("Keep awake", selection: $session.settingsDuration) {
                    ForEach(Self.durations, id: \.1) { Text($0.0).tag($0.1) }
                }
                .disabled(session.isActive)

                if !helperReady {
                    Text("The first time you turn Ajar on, it will ask for your password to install its helper.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { session.launchAtLogin },
                    set: { session.launchAtLogin = $0 }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private var helperReady: Bool {
        if case .installed = session.helperState { return true }
        return false
    }
}

private struct SafetyTab: View {
    @EnvironmentObject private var session: SessionController

    var body: some View {
        Form {
            Section("Temperature") {
                LabeledContent("Battery now", value: session.temperatureDescription)
                LabeledContent("macOS thermal state", value: session.thermalStateName)
                Toggle("Stop when the battery gets hot", isOn: $session.temperatureLimitEnabled)
                Picker("Limit", selection: $session.temperatureLimit) {
                    ForEach(SessionController.temperatureLimits, id: \.self) { Text("\($0)°C").tag($0) }
                }
                .disabled(!session.temperatureLimitEnabled)
                Toggle("Warn \(SessionController.warningMargin)°C before the limit", isOn: $session.temperatureWarning)
                    .disabled(!session.temperatureLimitEnabled)
                Toggle("Stop when macOS reports the Mac running hot", isOn: $session.thermalProtection)
            }
            Section("Power") {
                Toggle("Stop at low battery", isOn: $session.stopBelowBattery)
                Picker("Low battery level", selection: $session.batteryThreshold) {
                    ForEach([10, 20, 30, 50], id: \.self) { Text("\($0)%").tag($0) }
                }
                .disabled(!session.stopBelowBattery)
                Toggle("Stop when unplugged", isOn: $session.stopWhenUnplugged)
            }
            Section {
                Text("Even if Ajar hangs, its helper restores normal sleep at \(Int(AjarConstants.hardTemperatureLimit))°C or when macOS reports a critical thermal state.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HelperTab: View {
    @EnvironmentObject private var session: SessionController

    var body: some View {
        Form {
            Section("Helper") {
                LabeledContent("Status", value: session.helperDescription)
                LabeledContent("Install method", value: HelperInstaller.usesServiceManagement ? "System Settings (signed build)" : "LaunchDaemon (development build)")
                LabeledContent("System sleep disabled", value: session.systemSleepDisabled ? "Yes" : "No")
                HStack {
                    switch session.helperState {
                    case .needsApproval:
                        Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
                    case .installed:
                        Button("Reinstall…") { session.installHelper() }
                    case .unknown, .notInstalled:
                        Button("Install Helper…") { session.installHelper() }
                    }
                    Button("Uninstall…") { session.uninstallHelper() }
                        .disabled(session.helperState == .notInstalled)
                }
            }
            Section("Diagnostics") {
                Text("Copies system power state, helper status and recent errors, useful for bug reports.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Copy Diagnostics") { session.copyDiagnostics() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            Text("Ajar").font(.title.bold())
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .foregroundStyle(.secondary)
            Text("Keep your Mac awake with the lid closed, safely.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
