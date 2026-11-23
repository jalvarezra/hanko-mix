public enum PermissionStatus: Sendable, Equatable {
    case authorized, denied, unknown
}

/// Decides whether taps may be created and which permission notice to show.
public enum PermissionGate {
    public enum Notice: Sendable, Equatable {
        /// Explain why the permission is needed before macOS asks.
        case explain
        /// The user denied it: point them to Privacy settings.
        case denied
    }

    public struct Decision: Sendable, Equatable {
        public var allowTaps: Bool
        public var notice: Notice?
        public init(allowTaps: Bool, notice: Notice?) {
            self.allowTaps = allowTaps
            self.notice = notice
        }
    }

    public static func decide(explained: Bool, status: PermissionStatus, wantsTaps: Bool) -> Decision {
        switch status {
        case .authorized:
            return Decision(allowTaps: true, notice: nil)
        case .denied:
            // A tap without permission would mute the app and deliver silence.
            return Decision(allowTaps: false, notice: wantsTaps ? .denied : nil)
        case .unknown:
            return explained ? Decision(allowTaps: true, notice: nil)
                             : Decision(allowTaps: false, notice: wantsTaps ? .explain : nil)
        }
    }
}
