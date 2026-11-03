//
//  InputForwarder.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import AppKit

/// Handles coordinate transformations and forwards mouse, touch, and keyboard events to Android.
public final class InputForwarder: @unchecked Sendable {
    // MARK: - Callbacks for Protocol Packets

    public var onSendTouchEvent: ((TouchEventPayload) -> Void)?
    public var onSendKeyEvent: ((KeyEventPayload) -> Void)?
    public var onSendScrollEvent: ((ScrollEventPayload) -> Void)?
    public var onSendNavigation: ((NavigationPayload) -> Void)?

    // MARK: - State Properties

    public var targetScreenWidth: Int = 1080
    public var targetScreenHeight: Int = 2400

    private var isMouseDown: Bool = false
    private let queue = DispatchQueue(label: "com.droidlink.inputforwarder", qos: .userInteractive)

    // MARK: - Shared Instance

    public static let shared = InputForwarder()

    public init() {}

    // MARK: - Screen Dimension Updates

    public func updateTargetDimensions(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        self.targetScreenWidth = width
        self.targetScreenHeight = height
    }

    // MARK: - Mouse / Touch Event Forwarding

    /// Processes an `NSEvent` mouse down event within the MTKView coordinates
    public func handleMouseDown(event: NSEvent, in view: NSView, viewportRect: CGRect) {
        isMouseDown = true
        guard let (normX, normY) = mapCoordinates(event: event, in: view, viewportRect: viewportRect) else { return }

        let screenX = Int(normX * Float(targetScreenWidth))
        let screenY = Int(normY * Float(targetScreenHeight))

        let payload = TouchEventPayload(
            action: .down,
            pointerId: 0,
            normalizedX: normX,
            normalizedY: normY,
            screenX: screenX,
            screenY: screenY,
            pressure: 1.0,
            buttons: 1
        )
        onSendTouchEvent?(payload)
    }

    /// Processes an `NSEvent` mouse dragged event
    public func handleMouseDragged(event: NSEvent, in view: NSView, viewportRect: CGRect) {
        guard isMouseDown else { return }
        guard let (normX, normY) = mapCoordinates(event: event, in: view, viewportRect: viewportRect) else { return }

        let screenX = Int(normX * Float(targetScreenWidth))
        let screenY = Int(normY * Float(targetScreenHeight))

        let payload = TouchEventPayload(
            action: .move,
            pointerId: 0,
            normalizedX: normX,
            normalizedY: normY,
            screenX: screenX,
            screenY: screenY,
            pressure: 1.0,
            buttons: 1
        )
        onSendTouchEvent?(payload)
    }

    /// Processes an `NSEvent` mouse up event
    public func handleMouseUp(event: NSEvent, in view: NSView, viewportRect: CGRect) {
        guard isMouseDown else { return }
        isMouseDown = false
        guard let (normX, normY) = mapCoordinates(event: event, in: view, viewportRect: viewportRect) else { return }

        let screenX = Int(normX * Float(targetScreenWidth))
        let screenY = Int(normY * Float(targetScreenHeight))

        let payload = TouchEventPayload(
            action: .up,
            pointerId: 0,
            normalizedX: normX,
            normalizedY: normY,
            screenX: screenX,
            screenY: screenY,
            pressure: 0.0,
            buttons: 0
        )
        onSendTouchEvent?(payload)
    }

    /// Processes a right mouse click (maps to Android Back button)
    public func handleRightMouseUp(event: NSEvent) {
        onSendNavigation?(NavigationPayload(target: .back))
    }

    /// Processes scroll wheel events (smooth scrolling)
    public func handleScrollWheel(event: NSEvent, in view: NSView, viewportRect: CGRect) {
        guard let (normX, normY) = mapCoordinates(event: event, in: view, viewportRect: viewportRect) else { return }

        let deltaX = Float(event.scrollingDeltaX)
        let deltaY = Float(event.scrollingDeltaY)

        let payload = ScrollEventPayload(
            normalizedX: normX,
            normalizedY: normY,
            deltaX: deltaX,
            deltaY: deltaY
        )
        onSendScrollEvent?(payload)
    }

    // MARK: - Keyboard Event Forwarding

    /// Maps Mac `NSEvent` key down to Android KeyEvent
    public func handleKeyDown(event: NSEvent) -> Bool {
        // Handle Mac shortcuts like Cmd+C, Cmd+V, Cmd+A
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c":
                // Copy handled by macOS or pass through
                return false
            case "v":
                // Paste handled by clipboard sync
                return false
            case "a":
                // Select all: KEYCODE_A with META_CTRL_ON
                sendKeyEvent(keyCode: AndroidKeyCode.a.rawValue, action: 0, metaState: AndroidMetaKey.ctrlOn.rawValue)
                sendKeyEvent(keyCode: AndroidKeyCode.a.rawValue, action: 1, metaState: AndroidMetaKey.ctrlOn.rawValue)
                return true
            case "h":
                // Home navigation
                onSendNavigation?(NavigationPayload(target: .home))
                return true
            case "b":
                // Back navigation
                onSendNavigation?(NavigationPayload(target: .back))
                return true
            default:
                break
            }
        }

        if let androidCode = mapMacKeyCodeToAndroid(keyCode: event.keyCode) {
            let metaState = mapModifiers(event.modifierFlags)
            sendKeyEvent(keyCode: androidCode, action: 0, metaState: metaState, char: event.characters)
            return true
        }

        return false
    }

    /// Maps Mac `NSEvent` key up to Android KeyEvent
    public func handleKeyUp(event: NSEvent) -> Bool {
        if let androidCode = mapMacKeyCodeToAndroid(keyCode: event.keyCode) {
            let metaState = mapModifiers(event.modifierFlags)
            sendKeyEvent(keyCode: androidCode, action: 1, metaState: metaState, char: event.characters)
            return true
        }
        return false
    }

    private func sendKeyEvent(keyCode: Int, action: Int, metaState: Int = 0, char: String? = nil) {
        let payload = KeyEventPayload(keyCode: keyCode, action: action, metaState: metaState, character: char)
        onSendKeyEvent?(payload)
    }

    // MARK: - Coordinate Mapping Math

    /// Converts Mac view coordinates (flipped or standard) into normalized 0.0...1.0 video space
    private func mapCoordinates(event: NSEvent, in view: NSView, viewportRect: CGRect) -> (Float, Float)? {
        let locationInView = view.convert(event.locationInWindow, from: nil)

        // MTKView coordinates in AppKit: (0,0) is bottom-left, Android is top-left
        let viewHeight = view.bounds.height
        let flippedY = viewHeight - locationInView.y

        // Viewport rect contains the aspect-fit video frame inside view bounds
        let effectiveViewport = viewportRect.isEmpty ? view.bounds : viewportRect

        guard effectiveViewport.contains(CGPoint(x: locationInView.x, y: flippedY)) else {
            return nil
        }

        let relX = (locationInView.x - effectiveViewport.origin.x) / effectiveViewport.width
        let relY = (flippedY - effectiveViewport.origin.y) / effectiveViewport.height

        let clampedX = Float(max(0.0, min(1.0, relX)))
        let clampedY = Float(max(0.0, min(1.0, relY)))

        return (clampedX, clampedY)
    }

    // MARK: - Keycode Mappings

    private func mapModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var meta = 0
        if flags.contains(.shift) { meta |= AndroidMetaKey.shiftOn.rawValue }
        if flags.contains(.control) { meta |= AndroidMetaKey.ctrlOn.rawValue }
        if flags.contains(.option) { meta |= AndroidMetaKey.altOn.rawValue }
        if flags.contains(.command) { meta |= AndroidMetaKey.metaOn.rawValue }
        return meta
    }

    private func mapMacKeyCodeToAndroid(keyCode: UInt16) -> Int? {
        // macOS virtual key codes mapping to Android AKEYCODE
        switch keyCode {
        case 36: return AndroidKeyCode.enter.rawValue       // Return
        case 51: return AndroidKeyCode.del.rawValue         // Backspace / Delete
        case 53: return AndroidKeyCode.escape.rawValue      // Escape -> Back
        case 48: return AndroidKeyCode.tab.rawValue         // Tab
        case 49: return AndroidKeyCode.space.rawValue       // Space
        case 123: return AndroidKeyCode.dpadLeft.rawValue   // Left Arrow
        case 124: return AndroidKeyCode.dpadRight.rawValue  // Right Arrow
        case 125: return AndroidKeyCode.dpadDown.rawValue   // Down Arrow
        case 126: return AndroidKeyCode.dpadUp.rawValue     // Up Arrow
        case 115: return AndroidKeyCode.moveHome.rawValue   // Home
        case 119: return AndroidKeyCode.moveEnd.rawValue    // End
        case 116: return AndroidKeyCode.pageUp.rawValue     // Page Up
        case 121: return AndroidKeyCode.pageDown.rawValue   // Page Down
        // Letters A-Z
        case 0: return AndroidKeyCode.a.rawValue
        case 11: return AndroidKeyCode.b.rawValue
        case 8: return AndroidKeyCode.c.rawValue
        case 2: return AndroidKeyCode.d.rawValue
        case 14: return AndroidKeyCode.e.rawValue
        case 3: return AndroidKeyCode.f.rawValue
        case 5: return AndroidKeyCode.g.rawValue
        case 4: return AndroidKeyCode.h.rawValue
        case 34: return AndroidKeyCode.i.rawValue
        case 38: return AndroidKeyCode.j.rawValue
        case 40: return AndroidKeyCode.k.rawValue
        case 37: return AndroidKeyCode.l.rawValue
        case 46: return AndroidKeyCode.m.rawValue
        case 45: return AndroidKeyCode.n.rawValue
        case 31: return AndroidKeyCode.o.rawValue
        case 35: return AndroidKeyCode.p.rawValue
        case 12: return AndroidKeyCode.q.rawValue
        case 15: return AndroidKeyCode.r.rawValue
        case 1: return AndroidKeyCode.s.rawValue
        case 17: return AndroidKeyCode.t.rawValue
        case 32: return AndroidKeyCode.u.rawValue
        case 9: return AndroidKeyCode.v.rawValue
        case 13: return AndroidKeyCode.w.rawValue
        case 7: return AndroidKeyCode.x.rawValue
        case 16: return AndroidKeyCode.y.rawValue
        case 6: return AndroidKeyCode.z.rawValue
        // Numbers 0-9
        case 29: return AndroidKeyCode.num0.rawValue
        case 18: return AndroidKeyCode.num1.rawValue
        case 19: return AndroidKeyCode.num2.rawValue
        case 20: return AndroidKeyCode.num3.rawValue
        case 21: return AndroidKeyCode.num4.rawValue
        case 23: return AndroidKeyCode.num5.rawValue
        case 22: return AndroidKeyCode.num6.rawValue
        case 26: return AndroidKeyCode.num7.rawValue
        case 28: return AndroidKeyCode.num8.rawValue
        case 25: return AndroidKeyCode.num9.rawValue
        default: return nil
        }
    }
}

// MARK: - Android Key Codes Constants

public enum AndroidKeyCode: Int {
    case unknown = 0
    case home = 3
    case back = 4
    case call = 5
    case endcall = 6
    case num0 = 7
    case num1 = 8
    case num2 = 9
    case num3 = 10
    case num4 = 11
    case num5 = 12
    case num6 = 13
    case num7 = 14
    case num8 = 15
    case num9 = 16
    case dpadUp = 19
    case dpadDown = 20
    case dpadLeft = 21
    case dpadRight = 22
    case dpadCenter = 23
    case volumeUp = 24
    case volumeDown = 25
    case power = 26
    case camera = 27
    case clear = 28
    case a = 29
    case b = 30
    case c = 31
    case d = 32
    case e = 33
    case f = 34
    case g = 35
    case h = 36
    case i = 37
    case j = 38
    case k = 39
    case l = 40
    case m = 41
    case n = 42
    case o = 43
    case p = 44
    case q = 45
    case r = 46
    case s = 47
    case t = 48
    case u = 49
    case v = 50
    case w = 51
    case x = 52
    case y = 53
    case z = 54
    case comma = 55
    case period = 56
    case tab = 61
    case space = 62
    case enter = 66
    case del = 67
    case escape = 111
    case moveHome = 122
    case moveEnd = 123
    case pageUp = 92
    case pageDown = 93
    case appSwitch = 187
}

public enum AndroidMetaKey: Int {
    case shiftOn = 1
    case altOn = 2
    case symOn = 4
    case ctrlOn = 4096
    case metaOn = 65536
}
