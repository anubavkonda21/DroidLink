//
//  AndroidNotification.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

/// Represents a synchronized notification forwarded from the Android companion app.
public struct AndroidNotification: Identifiable, Codable, Equatable, Hashable, Sendable {
    // MARK: - Properties

    /// Unique identifier for the notification (package + notification key/id from Android)
    public var id: String

    /// User-friendly name of the originating Android app (e.g., "WhatsApp", "Gmail", "Slack")
    public var appName: String

    /// Android package identifier (e.g., "com.whatsapp", "com.google.android.gm")
    public var appPackage: String?

    /// App icon data as Base64 encoded PNG/JPEG, or SF symbol fallback identifier
    public var appIcon: String?

    /// Notification title / sender name
    public var title: String

    /// Notification content / message body
    public var body: String

    /// Timestamp when notification was posted on Android
    public var timestamp: Date

    /// Read / unread status
    public var isRead: Bool

    /// Indicates whether an inline text reply is supported by this notification
    public var canReply: Bool

    /// Available remote actions (e.g. "Mark as Read", "Archive", "Reply")
    public var actions: [NotificationAction]

    // MARK: - Nested Action Model

    public struct NotificationAction: Identifiable, Codable, Equatable, Hashable, Sendable {
        public var id: String
        public var title: String
        public var isQuickReply: Bool

        public init(id: String, title: String, isQuickReply: Bool = false) {
            self.id = id
            self.title = title
            self.isQuickReply = isQuickReply
        }
    }

    // MARK: - Initializer

    public init(
        id: String = UUID().uuidString,
        appName: String,
        appPackage: String? = nil,
        appIcon: String? = nil,
        title: String,
        body: String,
        timestamp: Date = Date(),
        isRead: Bool = false,
        canReply: Bool = false,
        actions: [NotificationAction] = []
    ) {
        self.id = id
        self.appName = appName
        self.appPackage = appPackage
        self.appIcon = appIcon
        self.title = title
        self.body = body
        self.timestamp = timestamp
        self.isRead = isRead
        self.canReply = canReply
        self.actions = actions
    }

    // MARK: - Computed Formatters

    /// Returns a human-friendly relative timestamp (e.g., "2m ago", "Just now", "Yesterday")
    public var relativeTimeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    /// Best effort fallback SF Symbol for recognized app categories
    public var fallbackSymbolName: String {
        let lowerName = appName.lowercased()
        let lowerPkg = (appPackage ?? "").lowercased()

        if lowerName.contains("whatsapp") || lowerPkg.contains("whatsapp") {
            return "message.badge.filled.fill"
        } else if lowerName.contains("slack") || lowerPkg.contains("slack") {
            return "number.square.fill"
        } else if lowerName.contains("mail") || lowerPkg.contains("gm") || lowerName.contains("gmail") {
            return "envelope.fill"
        } else if lowerName.contains("calendar") {
            return "calendar"
        } else if lowerName.contains("message") || lowerName.contains("sms") {
            return "bubble.left.and.bubble.right.fill"
        } else if lowerName.contains("phone") || lowerName.contains("call") {
            return "phone.fill"
        } else if lowerName.contains("bank") || lowerName.contains("pay") {
            return "creditcard.fill"
        } else {
            return "bell.fill"
        }
    }

    // MARK: - Previews & Mocks

    public static let mockNotifications: [AndroidNotification] = [
        AndroidNotification(
            id: "com.whatsapp|1001",
            appName: "WhatsApp",
            appPackage: "com.whatsapp",
            appIcon: nil,
            title: "Alex Morgan",
            body: "Are we still meeting at 3 PM for the product sync?",
            timestamp: Date().addingTimeInterval(-120),
            isRead: false,
            canReply: true,
            actions: [
                NotificationAction(id: "reply", title: "Reply", isQuickReply: true),
                NotificationAction(id: "mark_read", title: "Mark as read", isQuickReply: false)
            ]
        ),
        AndroidNotification(
            id: "com.google.android.gm|2044",
            appName: "Gmail",
            appPackage: "com.google.android.gm",
            appIcon: nil,
            title: "GitHub Notification",
            body: "[DroidLink/mac] New pull request #42: Implement VideoToolbox hardware decoding",
            timestamp: Date().addingTimeInterval(-900),
            isRead: false,
            canReply: false,
            actions: [
                NotificationAction(id: "archive", title: "Archive", isQuickReply: false)
            ]
        ),
        AndroidNotification(
            id: "com.slack|8823",
            appName: "Slack",
            appPackage: "com.slack",
            appIcon: nil,
            title: "#mobile-dev: Sarah Jenkins",
            body: "Pushed the updated companion APK to the artifact server.",
            timestamp: Date().addingTimeInterval(-3600),
            isRead: true,
            canReply: true,
            actions: [
                NotificationAction(id: "reply", title: "Reply", isQuickReply: true)
            ]
        ),
        AndroidNotification(
            id: "com.google.android.apps.messaging|9921",
            appName: "Messages",
            appPackage: "com.google.android.apps.messaging",
            appIcon: nil,
            title: "Chase Fraud Alert",
            body: "Your single-use verification code is 849201. Valid for 10 minutes.",
            timestamp: Date().addingTimeInterval(-7200),
            isRead: true,
            canReply: false,
            actions: []
        )
    ]
}
