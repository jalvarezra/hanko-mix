import Foundation

public enum FilterType: String, Codable, Sendable {
    case peaking, lowShelf, highShelf
}

public struct EQBand: Codable, Sendable, Equatable {
    public var type: FilterType
    public var frequency: Float
    public var gainDB: Float
    public var q: Float
    public var enabled: Bool = true

    public init(type: FilterType, frequency: Float, gainDB: Float, q: Float, enabled: Bool = true) {
        self.type = type
        self.frequency = frequency
        self.gainDB = gainDB
        self.q = q
        self.enabled = enabled
    }
}

/// Per-output-device processing settings (EQ, balance, mono).
public struct DeviceSettings: Codable, Sendable, Equatable {
    public static let maxBands = 10

    public var eqEnabled = false
    public var preampDB: Float = 0
    public var bands: [EQBand] = [] {
        didSet { if bands.count > Self.maxBands { bands = Array(bands.prefix(Self.maxBands)) } }
    }
    public var autoEQName: String? = nil
    public var balance: Float = 0
    public var mono = false

    public init() {}

    /// True when this device's processing would change the sound.
    public var isActive: Bool {
        (eqEnabled && (!bands.isEmpty || preampDB != 0)) || balance != 0 || mono
    }

    private enum CodingKeys: String, CodingKey {
        case eqEnabled, preampDB, bands, autoEQName, balance, mono
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        eqEnabled = try c.decodeIfPresent(Bool.self, forKey: .eqEnabled) ?? false
        preampDB = try c.decodeIfPresent(Float.self, forKey: .preampDB) ?? 0
        bands = Array((try c.decodeIfPresent([EQBand].self, forKey: .bands) ?? []).prefix(Self.maxBands))
        autoEQName = try c.decodeIfPresent(String.self, forKey: .autoEQName)
        balance = try c.decodeIfPresent(Float.self, forKey: .balance) ?? 0
        mono = try c.decodeIfPresent(Bool.self, forKey: .mono) ?? false
    }
}
