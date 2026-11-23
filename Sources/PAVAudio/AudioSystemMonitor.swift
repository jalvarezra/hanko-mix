import CoreAudio
import Foundation
import PAVCore

/// Reads output devices, the default output and audio processes from Core Audio, and
/// emits a debounced `SystemSnapshot` whenever any of them change (no polling).
public final class AudioSystemMonitor: @unchecked Sendable {
    public static let debounceInterval: TimeInterval = 0.1

    private let queue: DispatchQueue
    private let resolver: ProcessResolving
    private var onChange: (@Sendable (SystemSnapshot) -> Void)?
    private var pending: DispatchWorkItem?
    private var needsResubscribe = false
    private var objectListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    public init(queue: DispatchQueue, resolver: ProcessResolving = SystemProcessResolver()) {
        self.queue = queue
        self.resolver = resolver
    }

    // MARK: Snapshot

    public func currentSnapshot() throws -> SystemSnapshot {
        let devices = try outputDevices()
        let defaultID = try AudioObjectID.system.read(kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(0))
        let defaultUID = defaultID == 0 ? nil : try? defaultID.readString(kAudioDevicePropertyDeviceUID)
        let processes = try audioProcesses(knownDevices: devices.ids)
        let apps = AppGrouper.group(processes, ownPID: getpid(), resolver: resolver)
        return SystemSnapshot(apps: apps, devices: devices.list, defaultOutputUID: defaultUID,
                              ownProcessObjectIDs: ownProcessObjectID().map { [$0] } ?? [])
    }

    private func outputDevices() throws -> (list: [OutputDevice], ids: [AudioObjectID: String]) {
        var list: [OutputDevice] = []
        var ids: [AudioObjectID: String] = [:]
        for id in try AudioObjectID.system.readArray(kAudioHardwarePropertyDevices, of: AudioObjectID.self) {
            guard let uid = try? id.readString(kAudioDevicePropertyDeviceUID) else { continue }
            ids[id] = uid
            guard let channels = try? id.outputChannelCount(), channels > 0,
                  !uid.hasPrefix(Identifiers.uidPrefix) else { continue }
            let name = (try? id.readString(kAudioObjectPropertyName)) ?? uid
            let transport = (try? id.read(kAudioDevicePropertyTransportType, default: UInt32(0))) ?? 0
            let rate = (try? id.read(kAudioDevicePropertyNominalSampleRate, default: Float64(0))) ?? 0
            list.append(OutputDevice(uid: uid, name: name, transport: Self.transportKind(transport), sampleRate: rate, channels: channels))
        }
        return (list, ids)
    }

    private func audioProcesses(knownDevices: [AudioObjectID: String]) throws -> [AudioProcessInfo] {
        try AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self).compactMap { id in
            guard let pid = try? id.read(kAudioProcessPropertyPID, default: pid_t(0)), pid > 0 else { return nil }
            let bundleID = (try? id.readString(kAudioProcessPropertyBundleID)).flatMap { $0.isEmpty ? nil : $0 }
            let running = ((try? id.read(kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0) != 0
            let deviceIDs = (try? id.readArray(kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput, of: AudioObjectID.self)) ?? []
            return AudioProcessInfo(objectID: id, pid: pid, bundleID: bundleID, executablePath: resolver.executablePath(for: pid),
                                    isRunningOutput: running, outputDeviceUIDs: deviceIDs.compactMap { knownDevices[$0] })
        }
    }

    private func ownProcessObjectID() -> AudioObjectID? {
        var addr = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(.system, &addr, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func transportKind(_ value: UInt32) -> TransportKind {
        switch value {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeUSB: .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeAirPlay: .airPlay
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: .aggregate
        case kAudioDeviceTransportTypeVirtual: .virtual
        case kAudioDeviceTransportTypeHDMI: .hdmi
        case kAudioDeviceTransportTypeDisplayPort: .displayPort
        case kAudioDeviceTransportTypeThunderbolt: .thunderbolt
        default: .other
        }
    }

    // MARK: Listening

    public func start(onChange: @escaping @Sendable (SystemSnapshot) -> Void) {
        queue.async { [self] in
            self.onChange = onChange
            for selector in [kAudioHardwarePropertyProcessObjectList, kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
                var addr = address(selector)
                let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleEmit(resubscribe: true) }
                if AudioObjectAddPropertyListenerBlock(.system, &addr, queue, block) == noErr {
                    systemListeners.append((addr, block))
                }
            }
            resubscribeObjects()
            emit()
        }
    }

    public func stop() {
        queue.sync {
            for (addr, block) in systemListeners {
                var a = addr
                AudioObjectRemovePropertyListenerBlock(.system, &a, queue, block)
            }
            systemListeners.removeAll()
            removeObjectListeners()
            pending?.cancel()
            onChange = nil
        }
    }

    private func resubscribeObjects() {
        removeObjectListeners()
        let processes = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyProcessObjectList, of: AudioObjectID.self)) ?? []
        for id in processes {
            listen(id, address(kAudioProcessPropertyIsRunningOutput))
            listen(id, address(kAudioProcessPropertyDevices, kAudioObjectPropertyScopeOutput))
        }
        let devices = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyDevices, of: AudioObjectID.self)) ?? []
        for id in devices {
            listen(id, address(kAudioDevicePropertyNominalSampleRate))
        }
    }

    private func listen(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress) {
        var a = addr
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleEmit(resubscribe: false) }
        if AudioObjectAddPropertyListenerBlock(id, &a, queue, block) == noErr {
            objectListeners.append((id, addr, block))
        }
    }

    private func removeObjectListeners() {
        for (id, addr, block) in objectListeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(id, &a, queue, block)
        }
        objectListeners.removeAll()
    }

    /// Coalesces bursts of HAL notifications into one snapshot. Runs on `queue`.
    private func scheduleEmit(resubscribe: Bool) {
        pending?.cancel()
        needsResubscribe = needsResubscribe || resubscribe   // never lose a pending resubscribe
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.needsResubscribe {
                self.needsResubscribe = false
                self.resubscribeObjects()
            }
            self.emit()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    private func emit() {
        guard let onChange, let snapshot = try? currentSnapshot() else { return }
        onChange(snapshot)
    }
}
