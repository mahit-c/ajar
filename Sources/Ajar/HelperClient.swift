import Foundation
import AjarShared

/// Talks to the root helper over XPC. All completions run on the main queue; a nil
/// result means the helper could not be reached (not installed, not approved, or timed out).
final class HelperClient {
    struct Status {
        let sleepDisabled: Bool
        let sessionActive: Bool
        let version: String
    }

    var onInterruption: (() -> Void)?
    private var connection: NSXPCConnection?

    func status(_ completion: @escaping (Status?) -> Void) {
        call({ helper, done in
            helper.status { done(Status(sleepDisabled: $0, sessionActive: $1, version: $2)) }
        }, completion: completion)
    }

    func setSleepDisabled(_ disabled: Bool, completion: @escaping (_ error: String?) -> Void) {
        call({ helper, done in
            helper.setSleepDisabled(disabled) { ok, error in done(ok ? nil : (error ?? "Unknown helper error")) }
        }, completion: { result in
            completion(result ?? "Couldn't reach the Ajar helper.")
        })
    }

    func heartbeat() {
        call({ helper, done in helper.heartbeat { done(()) } }, completion: { _ in })
    }

    /// Used while the app is quitting, when the main queue can no longer service replies.
    func disableSynchronously() {
        guard let connection else { return }
        let proxy = connection.synchronousRemoteObjectProxyWithErrorHandler { _ in } as? AjarHelperProtocol
        proxy?.setSleepDisabled(false) { _, _ in }
    }

    private func currentConnection() -> NSXPCConnection {
        if let connection { return connection }
        let connection = NSXPCConnection(machServiceName: AjarConstants.helperLabel, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: AjarHelperProtocol.self)
        connection.interruptionHandler = { [weak self] in
            DispatchQueue.main.async { self?.onInterruption?() }
        }
        connection.invalidationHandler = { [weak self] in
            DispatchQueue.main.async { self?.connection = nil }
        }
        connection.resume()
        self.connection = connection
        return connection
    }

    private func call<T>(
        timeout: TimeInterval = 3,
        _ body: (AjarHelperProtocol, @escaping (T) -> Void) -> Void,
        completion: @escaping (T?) -> Void
    ) {
        var finished = false
        let finish: (T?) -> Void = { value in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                completion(value)
            }
        }
        let proxy = currentConnection().remoteObjectProxyWithErrorHandler { _ in finish(nil) }
        guard let helper = proxy as? AjarHelperProtocol else { return finish(nil) }
        body(helper) { finish($0) }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { finish(nil) }
    }
}
