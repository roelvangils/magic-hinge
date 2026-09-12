import CoreGraphics

/// Owns exactly one hide request and always balances it when the overlay goes away.
public final class EffectCursor {
    public private(set) var isHidden = false
    private let hide: () -> CGError
    private let show: () -> CGError
    public init(hide: @escaping () -> CGError = { CGDisplayHideCursor(CGMainDisplayID()) },
                show: @escaping () -> CGError = { CGDisplayShowCursor(CGMainDisplayID()) }) {
        self.hide = hide; self.show = show
    }
    @discardableResult public func setHidden(_ hidden: Bool) -> Bool {
        guard hidden != isHidden else { return true }
        let status = hidden ? hide() : show()
        if status == .success { isHidden = hidden; return true }
        return false
    }
    deinit { if isHidden { _ = show() } }
}
