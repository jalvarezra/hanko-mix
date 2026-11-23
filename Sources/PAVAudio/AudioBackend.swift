import PAVCore

public struct TapHandle: Hashable, Sendable {
    public var tapID: UInt32
    /// The tap's own UID (a UUID string assigned by Core Audio).
    public var uid: String
    public init(tapID: UInt32, uid: String) { self.tapID = tapID; self.uid = uid }
}

public struct AggregateHandle: Hashable, Sendable {
    public var deviceID: UInt32
    public var uid: String
    public init(deviceID: UInt32, uid: String) { self.deviceID = deviceID; self.uid = uid }
}

/// Side-effecting Core Audio operations, behind a protocol so `TapEngine` can be
/// tested with a fake.
public protocol AudioBackend: AnyObject {
    /// `deviceUID == nil`: stereo mixdown of `processObjectIDs`.
    /// `deviceUID != nil` and `exclusive`: everything playing on that device except `processObjectIDs`.
    func createTap(processObjectIDs: [UInt32], exclusive: Bool, deviceUID: String?, uid: String) throws -> TapHandle
    func updateTap(_ tap: TapHandle, processObjectIDs: [UInt32], exclusive: Bool) throws
    func destroyTap(_ tap: TapHandle)
    func createAggregate(uid: String, outputDeviceUID: String, tap: TapHandle) throws -> AggregateHandle
    func startIO(_ agg: AggregateHandle, chain: ProcessingChain) throws
    func stopIO(_ agg: AggregateHandle)
    func destroyAggregate(_ agg: AggregateHandle)
    func destroyStaleObjects(uidPrefix: String)
}
