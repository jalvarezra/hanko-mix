import Foundation
import PAVAudio
import PAVCore

// Developer diagnostics for PerAppVolume.
//   pav-diag list    — devices, default output and grouped audio apps
//   pav-diag watch   — print a snapshot on every change

func describe(_ snapshot: SystemSnapshot) -> String {
    var lines = ["Devices:"]
    for d in snapshot.devices {
        let mark = d.uid == snapshot.defaultOutputUID ? "*" : " "
        lines.append(" \(mark) \(d.name)  uid=\(d.uid)  transport=\(d.transport.rawValue)  rate=\(Int(d.sampleRate))  ch=\(d.channels)")
    }
    lines.append("Default output: \(snapshot.defaultOutputUID ?? "none")")
    lines.append("Apps:")
    for a in snapshot.apps {
        lines.append("   \(a.displayName)  id=\(a.id)  playing=\(a.isPlaying)  objects=\(a.processObjectIDs.sorted())  devices=\(a.outputDeviceUIDs)")
    }
    return lines.joined(separator: "\n")
}

func usage() -> Never {
    print("usage: pav-diag list | watch")
    exit(64)
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { usage() }
let queue = DispatchQueue(label: "pav-diag.audio")
let monitor = AudioSystemMonitor(queue: queue)

switch command {
case "list":
    do { print(describe(try monitor.currentSnapshot())) } catch { print("error: \(error)"); exit(1) }
case "watch":
    monitor.start { snapshot in
        print("— \(Date()) —\n\(describe(snapshot))\n")
    }
    dispatchMain()
default:
    usage()
}
