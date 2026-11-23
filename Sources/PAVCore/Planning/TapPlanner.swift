public enum TapKind: Hashable, Sendable {
    case app(AppID)
    case rest(deviceUID: String)
}

/// A tap that should exist: which processes it captures and where it plays.
public struct TapSpec: Hashable, Sendable {
    public var kind: TapKind
    public var processObjectIDs: Set<UInt32>
    public var exclusive: Bool
    public var outputDeviceUID: String
    public var outputSampleRate: Double

    public init(kind: TapKind, processObjectIDs: Set<UInt32>, exclusive: Bool, outputDeviceUID: String, outputSampleRate: Double) {
        self.kind = kind
        self.processObjectIDs = processObjectIDs
        self.exclusive = exclusive
        self.outputDeviceUID = outputDeviceUID
        self.outputSampleRate = outputSampleRate
    }

    /// When this changes the tap and its aggregate must be recreated; a change in
    /// `processObjectIDs` alone is applied in place.
    public struct StructuralKey: Hashable, Sendable {
        public var kind: TapKind
        public var exclusive: Bool
        public var outputDeviceUID: String
        public var outputSampleRate: Double
    }

    public var structuralKey: StructuralKey {
        StructuralKey(kind: kind, exclusive: exclusive, outputDeviceUID: outputDeviceUID, outputSampleRate: outputSampleRate)
    }
}

/// Computes the set of taps that should exist (spec §8.2–8.4). Pure function.
public enum TapPlanner {
    public static func plan(snapshot: SystemSnapshot, appSettings: [AppID: AppSettings],
                            deviceSettings: [String: DeviceSettings], keepAlive: Set<AppID>) -> [TapSpec] {
        var specs: [TapSpec] = []
        var tappedApps = Set<AppID>()
        var tappedProcesses = Set<UInt32>()

        for app in snapshot.apps {
            let settings = appSettings[app.id]
            let kept = keepAlive.contains(app.id)
            let needs = ProcessingRule.needsProcessing(app: app, settings: settings, deviceSettings: deviceSettings, snapshot: snapshot)
            guard (needs && app.isPlaying) || kept,
                  let output = ProcessingRule.effectiveOutputUID(for: app, settings: settings, snapshot: snapshot),
                  let device = snapshot.device(uid: output) else { continue }
            specs.append(TapSpec(kind: .app(app.id), processObjectIDs: app.processObjectIDs, exclusive: false,
                                 outputDeviceUID: output, outputSampleRate: device.sampleRate))
            tappedApps.insert(app.id)
            tappedProcesses.formUnion(app.processObjectIDs)
        }

        for device in snapshot.devices where deviceSettings[device.uid]?.isActive == true {
            let inUse = device.uid == snapshot.defaultOutputUID || snapshot.apps.contains {
                $0.isPlaying && !tappedApps.contains($0.id)
                    && ProcessingRule.automaticOutputUID(for: $0, snapshot: snapshot) == device.uid
            }
            guard inUse else { continue }
            specs.append(TapSpec(kind: .rest(deviceUID: device.uid), processObjectIDs: tappedProcesses, exclusive: true,
                                 outputDeviceUID: device.uid, outputSampleRate: device.sampleRate))
        }
        return specs
    }
}

/// Tracks apps whose tap stays alive (transparent) until they stop playing, so moving
/// a slider back to 100 % never recreates anything (spec §8.2, transitions).
public enum KeepAlive {
    public static func next(current: Set<AppID>, snapshot: SystemSnapshot, plannedApps: Set<AppID>) -> Set<AppID> {
        let playing = Set(snapshot.apps.filter(\.isPlaying).map(\.id))
        return current.union(plannedApps).intersection(playing)
    }
}
