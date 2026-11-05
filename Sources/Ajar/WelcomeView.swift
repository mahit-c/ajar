import ServiceManagement
import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject private var session: SessionController
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)
                Text("Welcome to Ajar")
                    .font(.largeTitle.bold())
                Text("Keep your Mac awake with the lid closed: for downloads, builds, renders, or anything that needs to finish while the laptop is shut.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                step(number: 1, title: "Install the helper", done: isInstalled) {
                    Text("macOS only lets a small privileged helper keep a closed laptop awake. It can do exactly one thing, switch sleep on or off, and Ajar turns sleep back on whenever you quit.")
                    helperControl
                }
                step(number: 2, title: "Find Ajar in the menu bar", done: false) {
                    Text("Look for \(Image(systemName: "moon.zzz")) at the top right of your screen. It turns into \(Image(systemName: "sun.max.fill")) while active.")
                    Text("Can't see it? Open Ajar again from Finder or Spotlight to get to Settings.")
                }
                step(number: 3, title: "Stay safe", done: false) {
                    Text("By default Ajar stops when the battery passes \(session.temperatureLimit)°C, drops below \(session.batteryThreshold)%, or macOS reports the Mac running hot. You can change this in Settings.")
                }
            }
            .padding(16)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Toggle("Launch Ajar at login", isOn: Binding(
                    get: { session.launchAtLogin },
                    set: { session.launchAtLogin = $0 }
                ))
                Spacer()
                Button("Done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    private var isInstalled: Bool {
        if case .installed = session.helperState { return true }
        return false
    }

    @ViewBuilder
    private var helperControl: some View {
        switch session.helperState {
        case .installed(let version):
            Label("Installed (v\(version))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .needsApproval:
            Button("Approve in System Settings…") { SMAppService.openSystemSettingsLoginItems() }
        case .unknown, .notInstalled:
            Button("Install Helper…") { session.installHelper() }
        }
        if let error = session.lastError {
            Text(error).foregroundStyle(.red).font(.callout)
        }
    }

    private func step<Content: View>(number: Int, title: String, done: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor).frame(width: 24, height: 24)
                if done {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.bold()).foregroundStyle(.white)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                content()
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
