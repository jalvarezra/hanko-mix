/// Decides where an app's audio goes and whether it must be intercepted (spec §8.2).
public enum ProcessingRule {
    /// The device the app is actually using, or the system default.
    public static func automaticOutputUID(for app: AppGroup, snapshot: SystemSnapshot) -> String? {
        app.outputDeviceUIDs.first { snapshot.device(uid: $0) != nil } ?? snapshot.defaultOutputUID
    }

    /// The assigned device when present; the system default when the assigned device
    /// is gone (spec §8.4); otherwise the automatic device.
    public static func effectiveOutputUID(for app: AppGroup, settings: AppSettings?, snapshot: SystemSnapshot) -> String? {
        if let assigned = settings?.outputDeviceUID {
            return snapshot.device(uid: assigned) != nil ? assigned : snapshot.defaultOutputUID
        }
        return automaticOutputUID(for: app, snapshot: snapshot)
    }

    /// True when the app's own settings (volume, mute, routing) change its sound, so
    /// it needs a tap of its own. Device EQ/balance/mono alone is handled by the
    /// device's "rest" tap instead.
    public static func needsOwnTap(app: AppGroup, settings: AppSettings?, snapshot: SystemSnapshot) -> Bool {
        guard let s = settings else { return false }
        if s.volume != 1 || s.muted { return true }
        if let effective = effectiveOutputUID(for: app, settings: s, snapshot: snapshot),
           effective != automaticOutputUID(for: app, snapshot: snapshot) { return true }
        return false
    }

    public static func needsProcessing(app: AppGroup, settings: AppSettings?, deviceSettings: [String: DeviceSettings], snapshot: SystemSnapshot) -> Bool {
        let effective = effectiveOutputUID(for: app, settings: settings, snapshot: snapshot)
        if let s = settings {
            if s.volume != 1 || s.muted { return true }
            if let effective, effective != automaticOutputUID(for: app, snapshot: snapshot) { return true }
        }
        if let effective, deviceSettings[effective]?.isActive == true { return true }
        return false
    }
}
