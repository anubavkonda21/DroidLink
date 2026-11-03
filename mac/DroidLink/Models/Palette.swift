//
//  Palette.swift
//  DroidLink
//
//  App colours in one place. AJ's choice: Apple blue, no purple/indigo/violet anywhere.
//  Status colours (green/orange/red) stay system colours.
//

import AppKit

extension NSColor {
    /// Main accent: icons, tiles, highlights. Fixed Apple blue, so it ignores the macOS accent setting.
    static let droidAccent = NSColor(srgbRed: 0x0A / 255.0, green: 0x84 / 255.0, blue: 0xFF / 255.0, alpha: 1)
}
