import Foundation
import PAVCore

/// Reads the "System Audio Recording" permission state. macOS has no public API for
/// it, so this uses the TCC preflight SPI when available and reports `.unknown`
/// otherwise (macOS then prompts on the first tap).
public enum AudioCapturePermission {
    private typealias PreflightFn = @convention(c) (CFString, CFDictionary?) -> Int

    private static let preflight: PreflightFn? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessPreflight") else { return nil }
        return unsafeBitCast(symbol, to: PreflightFn.self)
    }()

    public static func status() -> PermissionStatus {
        guard let preflight else { return .unknown }
        switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0: return .authorized
        case 1: return .denied
        default: return .unknown
        }
    }
}
