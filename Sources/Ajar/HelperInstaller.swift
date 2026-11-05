import Foundation
import Security
import ServiceManagement
import AjarShared

/// Installs the root helper. Builds signed with a Developer ID use SMAppService (one-time
/// approval in System Settings → Login Items). Ad-hoc dev builds can't use SMAppService
/// daemons reliably, so they fall back to a classic LaunchDaemon installed via an admin prompt.
enum HelperInstaller {
    struct InstallError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let label = AjarConstants.helperLabel
    static var daemon: SMAppService { SMAppService.daemon(plistName: "\(label).plist") }

    static var usesServiceManagement: Bool { signingTeamID != nil }

    static var needsApproval: Bool {
        usesServiceManagement && daemon.status == .requiresApproval
    }

    static func install() throws {
        if usesServiceManagement {
            try daemon.register()
            if daemon.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } else {
            try runPrivileged(legacyInstallScript, prompt: "Ajar needs to install a helper to keep your Mac awake with the lid closed.")
        }
    }

    static func uninstall() throws {
        if usesServiceManagement {
            try daemon.unregister()
        } else {
            try runPrivileged(legacyUninstallScript, prompt: "Ajar needs permission to remove its helper.")
        }
    }

    static var signingTeamID: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static var legacyInstallScript: String {
        let contents = Bundle.main.bundleURL.appendingPathComponent("Contents")
        let helper = contents.appendingPathComponent("MacOS/AjarHelper").path
        let plist = contents.appendingPathComponent("Resources/\(label).legacy.plist").path
        return """
        set -e
        launchctl bootout system/\(label) 2>/dev/null || true
        mkdir -p /Library/PrivilegedHelperTools
        install -o root -g wheel -m 755 \(quoted(helper)) /Library/PrivilegedHelperTools/\(label)
        install -o root -g wheel -m 644 \(quoted(plist)) /Library/LaunchDaemons/\(label).plist
        for i in 1 2 3 4 5; do launchctl bootstrap system /Library/LaunchDaemons/\(label).plist 2>/dev/null && break; sleep 1; done
        launchctl print system/\(label) >/dev/null
        """
    }

    private static var legacyUninstallScript: String {
        """
        launchctl bootout system/\(label) 2>/dev/null || true
        rm -f /Library/PrivilegedHelperTools/\(label) /Library/LaunchDaemons/\(label).plist
        rm -rf '/Library/Application Support/Ajar'
        pmset -a disablesleep 0
        """
    }

    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runPrivileged(_ script: String, prompt: String) throws {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        let source = "do shell script \"\(escape(script))\" with prompt \"\(escape(prompt))\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return }
        if error[NSAppleScript.errorNumber] as? Int == -128 { throw InstallError(message: "Cancelled.") }
        throw InstallError(message: error[NSAppleScript.errorMessage] as? String ?? "\(error)")
    }
}
