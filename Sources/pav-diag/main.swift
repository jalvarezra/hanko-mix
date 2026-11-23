import Foundation
import PAVAudio
import PAVCore

// Developer diagnostics for PerAppVolume.
//   pav-diag list    — devices, default output and grouped audio apps
//   pav-diag watch   — print a snapshot on every change
//   pav-diag tap --app <bundleID> --volume <0…2> [--output <deviceUID>]
//                    — tap one app through the real backend until Ctrl-C

func describe(_ snapshot: SystemSnapshot) -> String {
    var lines = ["Devices:"]
    for d in snapshot.devices {
        let mark = d.uid == snapshot.defaultOutputUID ? "*" : " "
        lines.append(" \(mark) \(d.name)  uid=\(d.uid)  transport=\(d.transport.rawValue)  rate=\(Int(d.sampleRate))  ch=\(d.channels)")
    }
    lines.append("Default output: \(snapshot.defaultOutputUID ?? "none")")
    lines.append("Inputs:")
    for i in snapshot.inputDevices {
        let mark = i.uid == snapshot.defaultInputUID ? "*" : " "
        let volume = i.volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
        lines.append(" \(mark) \(i.name)  uid=\(i.uid)  volume=\(volume)\(i.volumeSettable ? "" : " (fixed)")  muted=\(i.muted.map(String.init) ?? "n/a")\(i.muteSettable ? "" : " (fixed)")")
    }
    lines.append("Apps:")
    for a in snapshot.apps {
        lines.append("   \(a.displayName)  id=\(a.id)  playing=\(a.isPlaying)  objects=\(a.processObjectIDs.sorted())  devices=\(a.outputDeviceUIDs)")
    }
    return lines.joined(separator: "\n")
}

func usage() -> Never {
    print("usage: pav-diag list | watch | tap --app <bundleID> --volume <0…2> [--output <deviceUID>]")
    exit(64)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func runTap(args: [String], monitor: AudioSystemMonitor) throws -> Never {
    guard let appID = option("--app", in: args), let volume = option("--volume", in: args).flatMap(Float.init),
          AppSettings.volumeRange.contains(volume) else { usage() }
    let snapshot = try monitor.currentSnapshot()
    guard let app = snapshot.apps.first(where: { $0.id.rawValue == appID }) else {
        print("app \(appID) has no audio process right now"); exit(1)
    }
    guard let outputUID = option("--output", in: args) ?? ProcessingRule.automaticOutputUID(for: app, snapshot: snapshot),
          let device = snapshot.device(uid: outputUID) else {
        print("output device not found"); exit(1)
    }
    let backend = CoreAudioBackend()
    let tap = try backend.createTap(processObjectIDs: Array(app.processObjectIDs), exclusive: false, deviceUID: nil,
                                    uid: Identifiers.tapUIDPrefix + "diag")
    let aggregate: AggregateHandle
    do {
        aggregate = try backend.createAggregate(uid: Identifiers.aggregateUIDPrefix + "diag-\(UUID().uuidString)",
                                                outputDeviceUID: outputUID, tap: tap)
    } catch {
        backend.destroyTap(tap)   // unmute the app before reporting
        throw error
    }
    let chain = ProcessingChain(channels: 2, maxFrames: 4096, sampleRate: device.sampleRate)
    chain.update(ChainParameters(gain: volume, muted: false, device: DeviceSettings(), sampleRate: device.sampleRate))
    do {
        try backend.startIO(aggregate, chain: chain)
    } catch {
        backend.destroyAggregate(aggregate)
        backend.destroyTap(tap)
        throw error
    }
    print("Tapping \(app.displayName) → \(device.name) at \(Int(volume * 100))% — Ctrl-C to stop")
    signal(SIGINT, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    source.setEventHandler {
        backend.destroyAggregate(aggregate)
        backend.destroyTap(tap)
        print("\nStopped.")
        exit(0)
    }
    source.resume()
    dispatchMain()
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
let queue = DispatchQueue(label: "pav-diag.audio")
let monitor = AudioSystemMonitor(queue: queue)

switch command {
case "list":
    do { print(describe(try monitor.currentSnapshot())) } catch { print("error: \(error)"); exit(1) }
case "tap":
    do { try runTap(args: Array(args.dropFirst()), monitor: monitor) } catch { print("error: \(error)"); exit(1) }
case "watch":
    monitor.start { snapshot in
        print("— \(Date()) —\n\(describe(snapshot))\n")
    }
    dispatchMain()
default:
    usage()
}
