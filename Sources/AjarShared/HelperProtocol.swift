import Foundation

public enum AjarConstants {
    public static let appBundleID = "io.github.mahit-c.ajar"
    public static let helperLabel = "io.github.mahit-c.ajar.helper"
    public static let helperVersion = "0.2.0"

    /// Backstop enforced by the helper even if the app hangs; the user's own limit
    /// (enforced by the app) is lower.
    public static let hardTemperatureLimit: Double = 55

    /// Set to your Apple Developer Team ID for release builds. The helper then only
    /// accepts connections from an Ajar build signed by that team. While nil (local,
    /// ad-hoc builds) it only checks the bundle identifier, which is NOT secure enough to ship.
    public static let teamID: String? = nil

    public static var clientRequirement: String {
        if let teamID {
            return "identifier \"\(appBundleID)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
        }
        return "identifier \"\(appBundleID)\""
    }
}

/// XPC interface exposed by the root helper. Deliberately tiny: the helper can only
/// toggle sleep on/off, never run arbitrary commands.
@objc public protocol AjarHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (_ ok: Bool, _ error: String?) -> Void)
    func status(reply: @escaping (_ sleepDisabled: Bool, _ sessionActive: Bool, _ version: String) -> Void)
    func heartbeat(reply: @escaping () -> Void)
}
