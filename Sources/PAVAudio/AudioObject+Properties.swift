import CoreAudio
import Foundation

public struct AudioError: Error, CustomStringConvertible {
    public let status: OSStatus
    public let context: String

    public init(status: OSStatus, context: String) {
        self.status = status
        self.context = context
    }

    public var description: String {
        let code = UInt32(bitPattern: status)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        let fourCC = bytes.allSatisfy { $0 >= 32 && $0 < 127 } ? " '\(String(decoding: bytes, as: UTF8.self))'" : ""
        return "\(context) failed (OSStatus \(status)\(fourCC))"
    }
}

@inline(__always)
func check(_ status: OSStatus, _ context: @autoclosure () -> String) throws {
    guard status == noErr else { throw AudioError(status: status, context: context()) }
}

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

extension AudioObjectID {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    func has(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
             element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var addr = address(selector, scope, element)
        return AudioObjectHasProperty(self, &addr)
    }

    func isSettable(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope,
                    element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var addr = address(selector, scope, element)
        guard AudioObjectHasProperty(self, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(self, &addr, &settable) == noErr && settable.boolValue
    }

    func write<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                  element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, _ value: T) throws {
        var addr = address(selector, scope, element)
        var v = value
        try check(AudioObjectSetPropertyData(self, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &v), "write \(selector.fourCC) on \(self)")
    }

    func read<T: BitwiseCopyable>(_ selector: AudioObjectPropertySelector,
                 scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                 element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                 default value: T) throws -> T {
        var addr = address(selector, scope, element)
        var result = value
        var size = UInt32(MemoryLayout<T>.size)
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &result), "read \(selector.fourCC) on \(self)")
        return result
    }

    func readArray<T>(_ selector: AudioObjectPropertySelector,
                      scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                      element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
                      of _: T.Type) throws -> [T] {
        var addr = address(selector, scope, element)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size), "size \(selector.fourCC) on \(self)")
        let count = Int(size) / MemoryLayout<T>.stride
        guard count > 0 else { return [] }
        return try [T](unsafeUninitializedCapacity: count) { buffer, initialized in
            try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, buffer.baseAddress!), "read \(selector.fourCC) on \(self)")
            initialized = Int(size) / MemoryLayout<T>.stride
        }
    }

    func readString(_ selector: AudioObjectPropertySelector,
                    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> String {
        var addr = address(selector, scope)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, &value), "read \(selector.fourCC) on \(self)")
        return value?.takeRetainedValue() as String? ?? ""
    }

    /// Total output channels from the stream configuration.
    func outputChannelCount() throws -> Int {
        try channelCount(scope: kAudioObjectPropertyScopeOutput)
    }

    /// Total channels for `scope` (input or output) from the stream configuration.
    func channelCount(scope: AudioObjectPropertyScope) throws -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(self, &addr, 0, nil, &size), "size stream configuration on \(self)")
        guard size > 0 else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        try check(AudioObjectGetPropertyData(self, &addr, 0, nil, &size, raw), "read stream configuration on \(self)")
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}

extension UInt32 {
    var fourCC: String {
        let bytes = [24, 16, 8, 0].map { UInt8((self >> UInt32($0)) & 0xFF) }
        return bytes.allSatisfy { $0 >= 32 && $0 < 127 } ? "'\(String(decoding: bytes, as: UTF8.self))'" : "\(self)"
    }
}
