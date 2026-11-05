import AppKit
import SwiftUI

/// Ajar lives in the menu bar, but shows a Dock icon while one of its windows is open
/// so the window behaves like a normal app window (⌘-Tab, Dock, focus).
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var welcomeWindow: NSWindow?
    private var settingsWindow: NSWindow?

    func showWelcome() {
        welcomeWindow = show(welcomeWindow, title: "Welcome to Ajar") {
            WelcomeView { [weak self] in
                SessionController.shared.hasCompletedOnboarding = true
                self?.welcomeWindow?.close()
            }
        }
    }

    func showSettings() {
        settingsWindow = show(settingsWindow, title: "Ajar Settings") { SettingsView() }
    }

    private func show<Content: View>(_ existing: NSWindow?, title: String, content: () -> Content) -> NSWindow {
        let window = existing ?? {
            let window = NSWindow(
                contentViewController: NSHostingController(
                    rootView: content().environmentObject(SessionController.shared)
                )
            )
            window.title = title
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            return window
        }()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === welcomeWindow {
            SessionController.shared.hasCompletedOnboarding = true
        }
        DispatchQueue.main.async {
            let anyOpen = [self.welcomeWindow, self.settingsWindow].contains { $0?.isVisible == true }
            if !anyOpen { NSApp.setActivationPolicy(.accessory) }
        }
    }
}
