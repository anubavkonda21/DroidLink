//
//  ClipboardItem.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import AppKit

/// Source origin of clipboard payload.
public enum ClipboardSource: String, Codable, CaseIterable, Sendable {
    case mac = "macOS"
    case android = "Android"

    public var iconName: String {
        switch self {
        case .mac:
            return "laptopcomputer"
        case .android:
            return "smartphone"
        }
    }
}

/// Content payload carried in clipboard synchronization.
public enum ClipboardContent: Codable, Equatable, Hashable, Sendable {
    case text(String)
    case image(Data)

    public var displayText: String {
        switch self {
        case .text(let str):
            return str
        case .image(let data):
            let size = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)
            return "Image (\(size))"
        }
    }

    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }
}

/// Represents an item stored in clipboard sync history.
public struct ClipboardItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    // MARK: - Properties

    public var id: UUID
    public var content: ClipboardContent
    public var source: ClipboardSource
    public var timestamp: Date
    public var isOTP: Bool
    public var otpCode: String?

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        content: ClipboardContent,
        source: ClipboardSource,
        timestamp: Date = Date(),
        isOTP: Bool = false,
        otpCode: String? = nil
    ) {
        self.id = id
        self.content = content
        self.source = source
        self.timestamp = timestamp
        self.isOTP = isOTP
        self.otpCode = otpCode
    }

    // MARK: - Helper Methods

    /// Copies this item's content to macOS system pasteboard
    @MainActor
    public func copyToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch content {
        case .text(let str):
            pasteboard.setString(str, forType: .string)
        case .image(let data):
            if let img = NSImage(data: data), let tiff = img.tiffRepresentation {
                pasteboard.setData(tiff, forType: .tiff)
            }
        }
    }

    // MARK: - Static Factory with OTP Detection

    public static func create(
        content: ClipboardContent,
        source: ClipboardSource,
        timestamp: Date = Date()
    ) -> ClipboardItem {
        var isOTP = false
        var otpCode: String? = nil

        if case .text(let text) = content {
            // Regex to identify 4-8 digit OTP verification codes
            let otpPattern = #"(?i)(?:otp|code|verification|pin|password|passcode|auth)[\s:=#-]*([0-9]{4,8})\b|\b([0-9]{4,8})\b"#
            if let regex = try? NSRegularExpression(pattern: otpPattern, options: []) {
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    let fullMatch = (text as NSString).substring(with: match.range)
                    let digits = fullMatch.filter { $0.isNumber }
                    if digits.count >= 4 && digits.count <= 8 {
                        isOTP = true
                        otpCode = digits
                    }
                }
            }
        }

        return ClipboardItem(
            content: content,
            source: source,
            timestamp: timestamp,
            isOTP: isOTP,
            otpCode: otpCode
        )
    }

    // MARK: - Mocks

    public static let mockItems: [ClipboardItem] = [
        ClipboardItem.create(
            content: .text("https://github.com/droidlink/droidlink-app"),
            source: .android,
            timestamp: Date().addingTimeInterval(-180)
        ),
        ClipboardItem.create(
            content: .text("Your verification code is: 489201"),
            source: .android,
            timestamp: Date().addingTimeInterval(-600)
        ),
        ClipboardItem.create(
            content: .text("curl -fsSL https://raw.githubusercontent.com/droidlink/setup.sh | bash"),
            source: .mac,
            timestamp: Date().addingTimeInterval(-1200)
        )
    ]
}
