/// AppKit may use negative numbers for windows that have no WindowServer counterpart.
/// Zero is kCGNullWindowID; neither it nor out-of-range values may enter a capture filter.
public enum WindowCaptureID {
    public static func from(windowNumber: Int) -> UInt32? {
        guard windowNumber > 0 else { return nil }
        return UInt32(exactly: windowNumber)
    }
}
