//
//  GlossyTrafficLights.swift
//  DroidLink
//
//  AJ's choice: the window's close / minimize / zoom buttons match AJ's reference
//  screenshot: solid red, yellow, green balls that lighten toward the bottom, with a thin bright rim.
//  Each glossy ball is drawn as a subview inside macOS's own button, so it always sits
//  exactly where macOS puts the button and the window title layout never changes.
//

import AppKit
import ObjectiveC

enum GlossyTrafficLights {
    private static var observer: NSObjectProtocol?
    private static var key: UInt8 = 0

    /// Restyle every normal window as it appears. Call once at launch.
    static func installEverywhere() {
        guard observer == nil else { return }
        for w in NSApp.windows { install(on: w) }
        // Catch windows created later (Settings, onboarding, add-device) when they come forward.
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { note in
            if let w = note.object as? NSWindow { install(on: w) }
        }
    }

    /// Restyle one window. Safe to call more than once.
    static func install(on window: NSWindow) {
        guard !(window is NSPanel),               // open/save panels and floating bars keep their own look
              window.styleMask.contains(.titled),
              window.standardWindowButton(.closeButton) != nil,
              objc_getAssociatedObject(window, &key) == nil
        else { return }
        objc_setAssociatedObject(window, &key, GlossyButtonGroup(window: window), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

/// Shared state for one window's three balls (hover, active/inactive).
final class GlossyButtonGroup: NSObject {
    private weak var targetWindow: NSWindow?
    private var buttons: [GlossyWindowButton] = []
    private var tokens: [NSObjectProtocol] = []
    private var hoverCount = 0

    init(window: NSWindow) {
        targetWindow = window
        super.init()
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let sys = window.standardWindowButton(kind) else { continue }
            let b = GlossyWindowButton(kind: kind, system: sys, group: self)
            b.frame = sys.bounds
            b.autoresizingMask = [.width, .height]
            sys.addSubview(b)
            buttons.append(b)
        }
        let redraw: (Notification) -> Void = { [weak self] _ in self?.redraw() }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification,
                     NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main, using: redraw))
        }
    }

    deinit { tokens.forEach { NotificationCenter.default.removeObserver($0) } }

    var isHovering: Bool { hoverCount > 0 }
    var windowIsActive: Bool { targetWindow?.isKeyWindow == true || targetWindow?.isMainWindow == true }

    func hoverChanged(_ entered: Bool) {
        hoverCount = max(0, hoverCount + (entered ? 1 : -1))
        redraw()
    }

    func redraw() { buttons.forEach { $0.needsDisplay = true } }
}

/// One glossy ball, sitting inside (and covering) macOS's own button.
final class GlossyWindowButton: NSView {
    let kind: NSWindow.ButtonType
    let system: NSButton
    private unowned let group: GlossyButtonGroup
    private var pressed = false { didSet { needsDisplay = true } }
    private var inside = false

    init(kind: NSWindow.ButtonType, system: NSButton, group: GlossyButtonGroup) {
        self.kind = kind
        self.system = system
        self.group = group
        super.init(frame: system.bounds)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(kind == .closeButton ? "Close" : kind == .miniaturizeButton ? "Minimize" : "Zoom")
        toolTip = system.toolTip
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool { perform(); return true }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        guard !inside else { return }
        inside = true
        group.hoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        guard inside else { return }
        inside = false
        group.hoverChanged(false)
    }

    // MARK: Clicks

    override func mouseDown(with event: NSEvent) {
        guard system.isEnabled else { return }
        pressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard system.isEnabled else { return }
        pressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard system.isEnabled else { return }
        let hit = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if hit { perform(option: event.modifierFlags.contains(.option)) }
    }

    private func perform(option: Bool = false) {
        guard let w = window else { return }
        switch kind {
        case .closeButton:
            w.performClose(nil)
        case .miniaturizeButton:
            w.performMiniaturize(nil)
        default:
            // Same as the system button: full screen, or plain zoom with Option held.
            if !option, w.collectionBehavior.contains(.fullScreenPrimary) || w.styleMask.contains(.resizable) {
                w.toggleFullScreen(nil)
            } else {
                w.performZoom(nil)
            }
        }
    }

    // MARK: Drawing

    /// top = color near the top, bottom = lighter color at the bottom, edge = thin bright rim.
    private struct Tint { let top: NSColor; let bottom: NSColor; let edge: NSColor; let glyph: NSColor }

    private func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    // Colors sampled from AJ's reference screenshot.
    private var tint: Tint {
        let colored = group.windowIsActive || group.isHovering
        if !system.isEnabled {
            return Tint(top: rgb(0x8A8A8E), bottom: rgb(0x9A9A9E), edge: rgb(0xB0B0B4), glyph: .clear)
        }
        if !colored {
            return Tint(top: rgb(0xA6A6AA), bottom: rgb(0xBDBDC1), edge: rgb(0xDADADE), glyph: rgb(0x4A4A50))
        }
        switch kind {
        case .closeButton:
            return Tint(top: rgb(0xE35B4F), bottom: rgb(0xDF7165), edge: rgb(0xFFA095), glyph: rgb(0x5A0B07))
        case .miniaturizeButton:
            return Tint(top: rgb(0xF0B500), bottom: rgb(0xF7D155), edge: rgb(0xFFDE62), glyph: rgb(0x6B4100))
        default:
            return Tint(top: rgb(0x4EBA00), bottom: rgb(0x72C351), edge: rgb(0x9BEC76), glyph: rgb(0x124A05))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = tint
        let d = floor(min(bounds.width, bounds.height))
        let ball = NSRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: ball).addClip()

        // 1. Body: a little lighter right at the top, then a soft round glow in the lower half.
        NSGradient(colors: [t.top.blended(withFraction: 0.3, of: t.edge)!, t.top, t.top],
                   atLocations: [0, 0.3, 1], colorSpace: .sRGB)!
            .draw(in: ball, angle: -90)
        let glow = NSPoint(x: ball.midX, y: ball.minY + d * 0.3)
        NSGradient(colors: [t.bottom, t.bottom.withAlphaComponent(0)])!
            .draw(fromCenter: glow, radius: d * 0.15, toCenter: glow, radius: d * 0.6, options: .drawsBeforeStartingLocation)

        // 2. Thin bright rim, strongest at the top and bottom, faint at the sides.
        let ring = NSBezierPath(ovalIn: ball)
        ring.append(NSBezierPath(ovalIn: ball.insetBy(dx: 1, dy: 1)))
        ring.windingRule = .evenOdd
        ring.addClip()
        NSGradient(colors: [t.edge, t.edge.withAlphaComponent(0), t.edge.withAlphaComponent(0), t.edge],
                   atLocations: [0, 0.3, 0.7, 1], colorSpace: .sRGB)!
            .draw(in: ball, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        if pressed {
            NSColor.black.withAlphaComponent(0.22).setFill()
            NSBezierPath(ovalIn: ball).fill()
        }

        // 3. Glyph on hover (× − +), like the real buttons.
        if group.isHovering, system.isEnabled { drawGlyph(in: ball, color: t.glyph) }
    }

    private func drawGlyph(in ball: NSRect, color: NSColor) {
        let c = NSPoint(x: ball.midX, y: ball.midY)
        let r = ball.width * 0.22
        let p = NSBezierPath()
        p.lineWidth = max(1.1, ball.width * 0.1)
        p.lineCapStyle = .round
        switch kind {
        case .closeButton:
            p.move(to: NSPoint(x: c.x - r, y: c.y - r)); p.line(to: NSPoint(x: c.x + r, y: c.y + r))
            p.move(to: NSPoint(x: c.x - r, y: c.y + r)); p.line(to: NSPoint(x: c.x + r, y: c.y - r))
        case .miniaturizeButton:
            p.move(to: NSPoint(x: c.x - r * 1.25, y: c.y)); p.line(to: NSPoint(x: c.x + r * 1.25, y: c.y))
        default:
            p.move(to: NSPoint(x: c.x - r * 1.2, y: c.y)); p.line(to: NSPoint(x: c.x + r * 1.2, y: c.y))
            p.move(to: NSPoint(x: c.x, y: c.y - r * 1.2)); p.line(to: NSPoint(x: c.x, y: c.y + r * 1.2))
        }
        color.withAlphaComponent(0.8).setStroke()
        p.stroke()
    }
}
