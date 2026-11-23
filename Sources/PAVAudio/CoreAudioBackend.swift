import CoreAudio
import Foundation
import PAVCore

/// Everything the real-time IOProc needs, allocated up front.
final class IOContext {
    static let maxFrames = 4096
    let chain: ProcessingChain
    let scratchIn = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames * 2)
    let scratchOut = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames * 2)

    init(chain: ProcessingChain) { self.chain = chain }

    deinit {
        scratchIn.deallocate()
        scratchOut.deallocate()
    }
}

/// IOProc: tap input (any channel count) → stereo scratch → ProcessingChain →
/// device output (first two channels, extra channels zeroed). Real-time safe:
/// no allocation, no locks, no I/O.
private let ioProc: AudioDeviceIOProc = { _, _, inputData, _, outputData, _, clientData in
    guard let clientData else { return noErr }
    let ctx = Unmanaged<IOContext>.fromOpaque(clientData).takeUnretainedValue()
    let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    let outputs = UnsafeMutableAudioBufferListPointer(outputData)

    // Silence every output buffer first.
    for buffer in outputs { if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) } }
    guard let input = inputs.first, let inData = input.mData, input.mNumberChannels > 0,
          let firstOut = outputs.first, firstOut.mNumberChannels > 0 else { return noErr }

    let inChannels = Int(input.mNumberChannels)
    let outChannels = Int(firstOut.mNumberChannels)
    let inFrames = Int(input.mDataByteSize) / (MemoryLayout<Float>.size * inChannels)
    let outFrames = Int(firstOut.mDataByteSize) / (MemoryLayout<Float>.size * outChannels)
    let frames = min(inFrames, outFrames, IOContext.maxFrames)

    let src = inData.assumingMemoryBound(to: Float.self)
    for f in 0..<frames {
        let l = src[f * inChannels]
        ctx.scratchIn[f * 2] = l
        ctx.scratchIn[f * 2 + 1] = inChannels > 1 ? src[f * inChannels + 1] : l
    }
    ctx.chain.process(input: ctx.scratchIn, output: ctx.scratchOut, frames: frames)

    if outputs.count >= 2 && outChannels == 1 {
        // Non-interleaved device: one buffer per channel.
        if let l = outputs[0].mData?.assumingMemoryBound(to: Float.self),
           let r = outputs[1].mData?.assumingMemoryBound(to: Float.self) {
            for f in 0..<frames { l[f] = ctx.scratchOut[f * 2]; r[f] = ctx.scratchOut[f * 2 + 1] }
        }
    } else if let dst = firstOut.mData?.assumingMemoryBound(to: Float.self) {
        for f in 0..<frames {
            if outChannels == 1 {
                dst[f] = (ctx.scratchOut[f * 2] + ctx.scratchOut[f * 2 + 1]) * 0.5
            } else {
                dst[f * outChannels] = ctx.scratchOut[f * 2]
                dst[f * outChannels + 1] = ctx.scratchOut[f * 2 + 1]
            }
        }
    }
    return noErr
}

/// Real `AudioBackend` using Core Audio process taps and private aggregate devices.
public final class CoreAudioBackend: AudioBackend, @unchecked Sendable {
    public static let ioBufferFrames: UInt32 = 256

    private var descriptions: [AudioObjectID: CATapDescription] = [:]
    private var ioProcs: [AudioObjectID: (AudioDeviceIOProcID, Unmanaged<IOContext>)] = [:]

    public init() {}

    public func createTap(processObjectIDs: [UInt32], exclusive: Bool, deviceUID: String?, uid: String) throws -> TapHandle {
        let ids = processObjectIDs.map { NSNumber(value: $0) }
        let description: CATapDescription
        if let deviceUID, exclusive {
            description = CATapDescription(__excludingProcesses: ids, andDeviceUID: deviceUID, withStream: 0)
        } else if exclusive {
            description = CATapDescription(__stereoGlobalTapButExcludeProcesses: ids)
        } else {
            description = CATapDescription(__stereoMixdownOfProcesses: ids)
        }
        description.name = Identifiers.objectName
        description.isPrivate = true
        description.muteBehavior = .mutedWhenTapped

        var tapID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")
        let tapUID = (try? tapID.readString(kAudioTapPropertyUID)) ?? description.uuid.uuidString
        descriptions[tapID] = description
        return TapHandle(tapID: tapID, uid: tapUID)
    }

    public func updateTap(_ tap: TapHandle, processObjectIDs: [UInt32], exclusive: Bool) throws {
        guard let description = descriptions[tap.tapID] else {
            throw AudioError(status: kAudioHardwareBadObjectError, context: "updateTap: unknown tap \(tap.tapID)")
        }
        description.__processes = processObjectIDs.map { NSNumber(value: $0) }
        description.isExclusive = exclusive
        var addr = address(kAudioTapPropertyDescription)
        // Core Audio expects a pointer to the object reference.
        var ref = Unmanaged.passUnretained(description)
        try check(AudioObjectSetPropertyData(tap.tapID, &addr, 0, nil, UInt32(MemoryLayout<Unmanaged<CATapDescription>>.size), &ref),
                  "set tap description")
    }

    public func destroyTap(_ tap: TapHandle) {
        descriptions[tap.tapID] = nil
        AudioHardwareDestroyProcessTap(tap.tapID)
    }

    public func createAggregate(uid: String, outputDeviceUID: String, tap: TapHandle) throws -> AggregateHandle {
        let composition = AggregateDescription.make(uid: uid, outputDeviceUID: outputDeviceUID, tapUID: tap.uid)
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &deviceID), "AudioHardwareCreateAggregateDevice")
        var frames = Self.ioBufferFrames
        var addr = address(kAudioDevicePropertyBufferFrameSize)
        AudioObjectSetPropertyData(deviceID, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &frames)
        return AggregateHandle(deviceID: deviceID, uid: uid)
    }

    public func startIO(_ agg: AggregateHandle, chain: ProcessingChain) throws {
        let context = Unmanaged.passRetained(IOContext(chain: chain))
        var procID: AudioDeviceIOProcID?
        do {
            try check(AudioDeviceCreateIOProcID(agg.deviceID, ioProc, context.toOpaque(), &procID), "AudioDeviceCreateIOProcID")
            guard let procID else { throw AudioError(status: kAudioHardwareUnspecifiedError, context: "IOProc ID missing") }
            ioProcs[agg.deviceID] = (procID, context)
            try check(AudioDeviceStart(agg.deviceID, procID), "AudioDeviceStart")
        } catch {
            if procID == nil { context.release() } else { stopIO(agg) }   // stopIO releases the context
            throw error
        }
    }

    public func stopIO(_ agg: AggregateHandle) {
        guard let (procID, context) = ioProcs.removeValue(forKey: agg.deviceID) else { return }
        AudioDeviceStop(agg.deviceID, procID)
        AudioDeviceDestroyIOProcID(agg.deviceID, procID)
        context.release()
    }

    public func destroyAggregate(_ agg: AggregateHandle) {
        stopIO(agg)
        AudioHardwareDestroyAggregateDevice(agg.deviceID)
    }

    public func destroyStaleObjects(uidPrefix: String) {
        let devices = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyDevices, of: AudioObjectID.self)) ?? []
        for id in devices {
            if let uid = try? id.readString(kAudioDevicePropertyDeviceUID), uid.hasPrefix(uidPrefix) {
                AudioHardwareDestroyAggregateDevice(id)
            }
        }
        let taps = (try? AudioObjectID.system.readArray(kAudioHardwarePropertyTapList, of: AudioObjectID.self)) ?? []
        for id in taps where descriptions[id] == nil {
            var addr = address(kAudioTapPropertyDescription)
            var value: Unmanaged<CATapDescription>?
            var size = UInt32(MemoryLayout<Unmanaged<CATapDescription>?>.size)
            guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr,
                  let description = value?.takeRetainedValue(), description.name == Identifiers.objectName else { continue }
            AudioHardwareDestroyProcessTap(id)
        }
    }
}
