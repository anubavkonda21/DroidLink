//
//  Palette.swift
//  DroidLink
//
//  App colours in one place (AJ's palette: indigo & violet). Status colours (green/orange/red) stay system colours.
//

import AppKit

extension NSColor {
    /// Main accent: icons, tiles, highlights.
    static let droidAccent = NSColor(srgbRed: 0x5E / 255.0, green: 0x5C / 255.0, blue: 0xE6 / 255.0, alpha: 1)
    /// Secondary glow used alongside the accent.
    static let droidGlow = NSColor(srgbRed: 0xBF / 255.0, green: 0x5A / 255.0, blue: 0xF2 / 255.0, alpha: 1)
}
