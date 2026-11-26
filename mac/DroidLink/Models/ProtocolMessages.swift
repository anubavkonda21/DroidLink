//
//  ProtocolMessages.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

/// Message types used in the DroidLink bidirectional control protocol.
public enum MessageType: String, Codable {
    // Session & Handshake
    case handshake = "handshake"
    case handshakeAck = "handshake_ack"
    case heartbeat = "heartbeat"
    case disconnect = "disconnect"

    // Notifications
    case notificationPost = "notification_post"
    case notificationDismiss = "notification_dismiss"
    case notificationReply = "notification_reply"
}

// MARK: - Generic Envelope

/// Encapsulates any DroidLink protocol packet with a typed header and JSON payload.
public struct ProtocolMessageEnvelope: Codable {
    public var type: MessageType
    public var timestamp: TimeInterval
    public var payloadData: Data?

    public init(type: MessageType, timestamp: TimeInterval = Date().timeIntervalSince1970, payloadData: Data? = nil) {
        self.type = type
        self.timestamp = timestamp
        self.payloadData = payloadData
    }

    /// Helper to encode a generic Codable payload
    public static func encode<T: Codable>(type: MessageType, payload: T) throws -> Data {
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        let payloadBytes = try jsonEncoder.encode(payload)
        let envelope = ProtocolMessageEnvelope(type: type, payloadData: payloadBytes)
        return try jsonEncoder.encode(envelope)
    }

    /// Helper to decode from an envelope
    public func decodePayload<T: Codable>(_ type: T.Type) throws -> T {
        guard let data = payloadData else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "Missing payload data"))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

// MARK: - Payload Definitions

/// Handshake initiated upon control channel connect
public struct HandshakePayload: Codable {
    public var clientVersion: String
    public var clientOS: String
    public var deviceName: String
    public var requestedFeatures: [String]

    public init(
        clientVersion: String = "1.0.0",
        clientOS: String = "macOS 14+",
        deviceName: String = Host.current().localizedName ?? "Mac",
        requestedFeatures: [String] = ["notifications"]
    ) {
        self.clientVersion = clientVersion
        self.clientOS = clientOS
        self.deviceName = deviceName
        self.requestedFeatures = requestedFeatures
    }
}

/// Inline notification reply
public struct NotificationReplyPayload: Codable {
    public var notificationId: String
    public var actionId: String?
    public var replyText: String

    public init(notificationId: String, actionId: String? = nil, replyText: String) {
        self.notificationId = notificationId
        self.actionId = actionId
        self.replyText = replyText
    }
}

/// Notification dismiss command
public struct NotificationDismissPayload: Codable {
    public var notificationId: String

    public init(notificationId: String) {
        self.notificationId = notificationId
    }
}

// MARK: - Binary Framing Helpers

public enum ProtocolFramer {
    /// Encodes a raw packet with a 4-byte big-endian length prefix
    public static func frame(data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(data)
        return framed
    }

    /// Extracts complete packets from an incoming buffer, returning remaining unprocessed bytes
    public static func deframe(buffer: inout Data) -> [Data] {
        var packets: [Data] = []
        while buffer.count >= 4 {
            let length = buffer.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let totalLength = Int(length) + 4
            guard buffer.count >= totalLength else {
                break
            }
            let packet = buffer.subdata(in: 4..<totalLength)
            packets.append(packet)
            buffer.removeSubrange(0..<totalLength)
        }
        return packets
    }
}
