import CoreGraphics
import Foundation
import IOKit

enum LidMonitor {
    /// true when the built-in display's lid is closed.
    static var isClosed: Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != 0 else { return false }
        defer { IOObjectRelease(rootDomain) }
        let value = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (value as? Bool) ?? false
    }

    /// An external display in use means the user is working in clamshell mode and must not
    /// be locked out. The built-in display is ignored: while sleep is disabled, macOS keeps
    /// reporting it as active and awake even with the lid shut.
    static var hasExternalDisplay: Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}

enum ScreenLocker {
    private typealias LockFunction = @convention(c) () -> Int32

    /// macOS has no public "lock now" API. SACLockScreenImmediate (login.framework) is the
    /// same call the system's ⌃⌘Q uses. If Apple removes it, fall back to sleeping the
    /// display, which locks according to the user's "Require password" setting.
    static func lockNow() {
        if let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_LAZY),
           let symbol = dlsym(handle, "SACLockScreenImmediate") {
            _ = unsafeBitCast(symbol, to: LockFunction.self)()
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        try? process.run()
    }
}
