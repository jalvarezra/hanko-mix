/// Makes slider values stick to their neutral position, so the user can get back to
/// exactly 100 % volume or a centered balance by dragging near it.
public enum Snap {
    public static let balanceTolerance: Float = 0.05
    public static let volumeTolerance: Float = 0.03

    public static func balance(_ value: Float) -> Float {
        abs(value) <= balanceTolerance ? 0 : value
    }

    public static func volume(_ value: Float) -> Float {
        abs(value - 1) <= volumeTolerance ? 1 : value
    }
}
