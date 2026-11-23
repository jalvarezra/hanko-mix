import Darwin
import Foundation

/// One Core Audio process object, as read from the HAL.
public struct AudioProcessInfo: Sendable, Hashable {
    public var objectID: UInt32
    public var pid: Int32
    public var bundleID: String?
    public var executablePath: String?
    public var isRunningOutput: Bool
    public var outputDeviceUIDs: [String]

    public init(objectID: UInt32, pid: Int32, bundleID: String?, executablePath: String?, isRunningOutput: Bool, outputDeviceUIDs: [String]) {
        self.objectID = objectID
        self.pid = pid
        self.bundleID = bundleID
        self.executablePath = executablePath
        self.isRunningOutput = isRunningOutput
        self.outputDeviceUIDs = outputDeviceUIDs
    }
}

public protocol ProcessResolving: Sendable {
    func responsiblePID(for pid: Int32) -> Int32?
    func executablePath(for pid: Int32) -> String?
    /// Bundle info of the outermost `.app` containing `path`.
    func bundleInfo(forExecutablePath path: String) -> (bundleID: String, name: String)?
}

/// Groups audio processes into apps as the user sees them (helpers fold into
/// their parent app).
public enum AppGrouper {
    public static func group(_ processes: [AudioProcessInfo], ownPID: Int32, resolver: ProcessResolving) -> [AppGroup] {
        var order: [AppID] = []
        var groups: [AppID: AppGroup] = [:]
        for process in processes where process.pid != ownPID {
            guard let (id, rawName) = resolve(process, ownPID: ownPID, resolver: resolver) else { continue }
            let name = FriendlyNames.displayName(for: id, fallback: rawName)
            if var group = groups[id] {
                group.processObjectIDs.insert(process.objectID)
                group.isPlaying = group.isPlaying || process.isRunningOutput
                for uid in process.outputDeviceUIDs where !group.outputDeviceUIDs.contains(uid) {
                    group.outputDeviceUIDs.append(uid)
                }
                groups[id] = group
            } else {
                order.append(id)
                var uids: [String] = []
                for uid in process.outputDeviceUIDs where !uids.contains(uid) { uids.append(uid) }
                groups[id] = AppGroup(id: id, displayName: name, processObjectIDs: [process.objectID],
                                      isPlaying: process.isRunningOutput, outputDeviceUIDs: uids)
            }
        }
        return order.compactMap { groups[$0] }
    }

    private static func resolve(_ p: AudioProcessInfo, ownPID: Int32, resolver: ProcessResolving) -> (AppID, String)? {
        if let responsible = resolver.responsiblePID(for: p.pid), responsible != p.pid, responsible != ownPID,
           let path = resolver.executablePath(for: responsible),
           let info = resolver.bundleInfo(forExecutablePath: path) {
            return (AppID(info.bundleID), info.name)
        }
        if let path = p.executablePath, let info = resolver.bundleInfo(forExecutablePath: path) {
            return (AppID(info.bundleID), info.name)
        }
        if let bundleID = p.bundleID { return (AppID(bundleID), bundleID) }
        if let path = p.executablePath { return (AppID(path), (path as NSString).lastPathComponent) }
        return nil
    }
}

/// Real resolver backed by libproc, `Bundle` and (when available) the
/// responsibility SPI used to map XPC services back to the app that owns them.
public struct SystemProcessResolver: ProcessResolving {
    private typealias ResponsibleFn = @convention(c) (pid_t) -> pid_t

    public init() {}

    public func responsiblePID(for pid: Int32) -> Int32? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
        let fn = unsafeBitCast(symbol, to: ResponsibleFn.self)
        let result = fn(pid)
        return result > 0 ? result : nil
    }

    public func executablePath(for pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    public func bundleInfo(forExecutablePath path: String) -> (bundleID: String, name: String)? {
        guard let range = path.range(of: ".app/") else { return nil }
        let appPath = String(path[..<range.lowerBound]) + ".app"
        guard let bundle = Bundle(path: appPath), let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        return (id, name)
    }
}
