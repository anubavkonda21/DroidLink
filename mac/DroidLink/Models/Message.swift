//
//  Message.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

/// Represents an SMS/MMS or chat message synchronized with the connected Android device.
public struct Message: Identifiable, Codable, Equatable, Hashable, Sendable {
    // MARK: - Properties

    public var id: UUID
    public var conversationId: String
    public var contactName: String
    public var contactNumber: String
    public var body: String
    public var timestamp: Date
    public var isIncoming: Bool
    public var isRead: Bool
    public var deliveryStatus: DeliveryStatus

    public enum DeliveryStatus: String, Codable, Sendable {
        case pending
        case sent
        case delivered
        case failed
    }

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        conversationId: String,
        contactName: String,
        contactNumber: String,
        body: String,
        timestamp: Date = Date(),
        isIncoming: Bool,
        isRead: Bool = true,
        deliveryStatus: DeliveryStatus = .delivered
    ) {
        self.id = id
        self.conversationId = conversationId
        self.contactName = contactName
        self.contactNumber = contactNumber
        self.body = body
        self.timestamp = timestamp
        self.isIncoming = isIncoming
        self.isRead = isRead
        self.deliveryStatus = deliveryStatus
    }

    // MARK: - Computed Formatters

    public var formattedTime: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(timestamp) {
            formatter.dateFormat = "h:mm a"
        } else if Calendar.current.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: timestamp)
    }
}

/// Represents a conversation thread with an Android contact.
public struct Conversation: Identifiable, Codable, Equatable, Hashable, Sendable {
    // MARK: - Properties

    public var id: String { contactNumber }
    public var contactName: String
    public var contactNumber: String
    public var avatarColorHex: String
    public var messages: [Message]
    public var unreadCount: Int

    public var lastMessage: Message? {
        messages.sorted(by: { $0.timestamp < $1.timestamp }).last
    }

    // MARK: - Initializer

    public init(
        contactName: String,
        contactNumber: String,
        avatarColorHex: String = "#0A84FF",
        messages: [Message] = [],
        unreadCount: Int = 0
    ) {
        self.contactName = contactName
        self.contactNumber = contactNumber
        self.avatarColorHex = avatarColorHex
        self.messages = messages
        self.unreadCount = unreadCount
    }

    // MARK: - Computed Properties

    public var initials: String {
        let parts = contactName.split(separator: " ")
        if parts.count >= 2, let first = parts.first?.first, let second = parts.last?.first {
            return "\(first)\(second)".uppercased()
        } else if let first = contactName.first {
            return String(first).uppercased()
        }
        return "#"
    }

    // MARK: - Previews & Mocks

    public static let mockConversations: [Conversation] = [
        Conversation(
            contactName: "Sarah Connor",
            contactNumber: "+1 (555) 234-5678",
            avatarColorHex: "#30D158",
            messages: [
                Message(conversationId: "+1 (555) 234-5678", contactName: "Sarah Connor", contactNumber: "+1 (555) 234-5678", body: "Hey! Did you see the updated mirror performance on Mac?", timestamp: Date().addingTimeInterval(-7200), isIncoming: true),
                Message(conversationId: "+1 (555) 234-5678", contactName: "Sarah Connor", contactNumber: "+1 (555) 234-5678", body: "Yes, latency is down to under 18ms over USB 3.0!", timestamp: Date().addingTimeInterval(-3600), isIncoming: false),
                Message(conversationId: "+1 (555) 234-5678", contactName: "Sarah Connor", contactNumber: "+1 (555) 234-5678", body: "Awesome. I'll test the wireless ADB mode this afternoon.", timestamp: Date().addingTimeInterval(-1800), isIncoming: true)
            ],
            unreadCount: 1
        ),
        Conversation(
            contactName: "David Miller",
            contactNumber: "+1 (555) 876-5432",
            avatarColorHex: "#BF5AF2",
            messages: [
                Message(conversationId: "+1 (555) 876-5432", contactName: "David Miller", contactNumber: "+1 (555) 876-5432", body: "Are we still meeting for lunch?", timestamp: Date().addingTimeInterval(-14400), isIncoming: true),
                Message(conversationId: "+1 (555) 876-5432", contactName: "David Miller", contactNumber: "+1 (555) 876-5432", body: "Sure, let's meet at 12:30 at the deli.", timestamp: Date().addingTimeInterval(-10800), isIncoming: false)
            ],
            unreadCount: 0
        ),
        Conversation(
            contactName: "Bank Alerts",
            contactNumber: "22000",
            avatarColorHex: "#FF9F0A",
            messages: [
                Message(conversationId: "22000", contactName: "Bank Alerts", contactNumber: "22000", body: "Your one-time passcode is 492018. It expires in 5 minutes.", timestamp: Date().addingTimeInterval(-600), isIncoming: true)
            ],
            unreadCount: 1
        )
    ]
}
