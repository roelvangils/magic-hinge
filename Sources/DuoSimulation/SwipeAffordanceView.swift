import AppKit
import QuartzCore

/// Decorative only: mouse and trackpad events pass straight through to the simulator.
final class SwipeAffordanceView: NSView {
    private var pointsDown = false
    private var dots: [CAShapeLayer] = []
    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        for x in [22.0,52.0] {
            let dot = CAShapeLayer()
            dot.path = CGPath(ellipseIn:CGRect(x:-10,y:-10,width:20,height:20),transform:nil)
            dot.fillColor = NSColor.white.cgColor
            dot.position = CGPoint(x:x,y:18)
            dot.opacity = 0
            layer?.addSublayer(dot); dots.append(dot)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    func setAnimating(_ enabled: Bool, pointsDown: Bool = false) {
        if self.pointsDown != pointsDown {
            self.pointsDown = pointsDown
            for dot in dots { dot.removeAllAnimations() }
        }
        isHidden = !enabled
        let start = CACurrentMediaTime()
        for dot in dots {
            if !enabled { dot.removeAllAnimations(); continue }
            guard dot.animation(forKey:"swipe") == nil else { continue }
            dot.position.y = pointsDown ? 70 : 18
            let movement = CABasicAnimation(keyPath:"transform.translation.y")
            movement.fromValue = 0; movement.toValue = pointsDown ? -40 : 40
            movement.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
            let opacity = CAKeyframeAnimation(keyPath:"opacity")
            opacity.values = [0,0.62,0.62,0,0]
            opacity.keyTimes = [0,0.15,0.35,0.8,1]
            let group = CAAnimationGroup()
            group.animations = [movement,opacity]; movement.duration = 2.1
            opacity.duration = 2.1
            group.duration = 2.1; group.beginTime = start
            group.repeatCount = .infinity
            // Both dots share the same layer timeline, keeping the gesture synchronized.
            dot.add(group,forKey:"swipe")
        }
    }
}
