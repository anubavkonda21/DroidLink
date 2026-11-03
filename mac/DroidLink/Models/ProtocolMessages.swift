//
//  ProtocolMessages.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

/// Defines all message types used in the DroidLink bidirectional control protocol.
public enum MessageType: String, Codable {
    // Session & Handshake
    case handshake = "handshake"
    case handshakeAck = "handshake_ack"
    case heartbeat = "heartbeat"
    case disconnect = "disconnect"

    // Remote Input Control
    case touchEvent = "touch_event"
    case keyEvent = "key_event"
    case textInput = "text_input"
    case scrollEvent = "scroll_event"
    case navigation = "navigation"

    // Device Actions
    case setScreenPower = "set_screen_power"
    case rotateDevice = "rotate_device"
    case findPhone = "find_phone"
    case volumeControl = "volume_control"

    // Ecosystem Sync
    case clipboardSync = "clipboard_sync"
    case notificationPost = "notification_post"
    case notificationDismiss = "notification_dismiss"
    case notificationReply = "notification_reply"
    case smsList = "sms_list"
    case smsSend = "sms_send"
    case callEvent = "call_event"
    case deviceStatusUpdate = "device_status_update"
    case macStatus = "mac_status"      // Mac -> phone: battery, storage, volume
    case macCommand = "mac_command"    // phone -> Mac: lock, sleep, volume, media

    // File Transfer
    case fileTransferInit = "file_transfer_init"
    case fileTransferAck = "file_transfer_ack"
    case fileTransferChunk = "file_transfer_chunk"
    case fileTransferComplete = "file_transfer_complete"
    case fileTransferCancel = "file_transfer_cancel"
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

/// Handshake initiated upon TCP/WebSocket connect
public struct HandshakePayload: Codable {
    public var clientVersion: String
    public var clientOS: String
    public var deviceName: String
    public var requestedFeatures: [String]

    public init(
        clientVersion: String = "1.0.0",
        clientOS: String = "macOS 14+",
        deviceName: String = Host.current().localizedName ?? "Mac",
        requestedFeatures: [String] = ["video", "audio", "input", "clipboard", "notifications", "sms", "files"]
    ) {
        self.clientVersion = clientVersion
        self.clientOS = clientOS
        self.deviceName = deviceName
        self.requestedFeatures = requestedFeatures
    }
}

/// Touch Action corresponding to Android MotionEvent
public enum TouchAction: Int, Codable {
    case down = 0
    case up = 1
    case move = 2
    case cancel = 3
    case pointerDown = 5
    case pointerUp = 6
}

/// Touch event forwarded to Android input subsystem
public struct TouchEventPayload: Codable {
    public var action: TouchAction
    public var pointerId: Int
    /// Normalized coordinates (0.0 to 1.0)
    public var normalizedX: Float
    public var normalizedY: Float
    /// Absolute Android screen coordinates
    public var screenX: Int
    public var screenY: Int
    public var pressure: Float
    public var buttons: Int

    public init(
        action: TouchAction,
        pointerId: Int = 0,
        normalizedX: Float,
        normalizedY: Float,
        screenX: Int,
        screenY: Int,
        pressure: Float = 1.0,
        buttons: Int = 1
    ) {
        self.action = action
        self.pointerId = pointerId
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.screenX = screenX
        self.screenY = screenY
        self.pressure = pressure
        self.buttons = buttons
    }
}

/// Key event corresponding to Android KeyEvent
public struct KeyEventPayload: Codable {
    public var keyCode: Int
    public var action: Int // 0 = Down, 1 = Up
    public var metaState: Int
    public var character: String?

    public init(keyCode: Int, action: Int, metaState: Int = 0, character: String? = nil) {
        self.keyCode = keyCode
        self.action = action
        self.metaState = metaState
        self.character = character
    }
}

/// Navigation quick actions (Back, Home, App Switcher / Recents)
public enum NavigationTarget: String, Codable {
    case back
    case home
    case recents
    case notifications
    case lockScreen
    case volumeUp
    case volumeDown
}

public struct NavigationPayload: Codable {
    public var target: NavigationTarget

    public init(target: NavigationTarget) {
        self.target = target
    }
}

/// Scroll wheel or trackpad gesture
public struct ScrollEventPayload: Codable {
    public var normalizedX: Float
    public var normalizedY: Float
    public var deltaX: Float
    public var deltaY: Float

    public init(normalizedX: Float, normalizedY: Float, deltaX: Float, deltaY: Float) {
        self.normalizedX = normalizedX
        self.normalizedY = normalizedY
        self.deltaX = deltaX
        self.deltaY = deltaY
    }
}

/// Synchronized clipboard payload
public struct ClipboardPayload: Codable {
    public var text: String?
    public var imageBase64: String?
    public var isHtml: Bool
    public var timestamp: TimeInterval

    public init(text: String? = nil, imageBase64: String? = nil, isHtml: Bool = false, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.text = text
        self.imageBase64 = imageBase64
        self.isHtml = isHtml
        self.timestamp = timestamp
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

/// Send SMS payload
public struct SendSMSPayload: Codable {
    public var recipientNumber: String
    public var messageBody: String

    public init(recipientNumber: String, messageBody: String) {
        self.recipientNumber = recipientNumber
        self.messageBody = messageBody
    }
}

/// Incoming / outgoing phone call event
public struct CallEventPayload: Codable {
    public enum CallState: String, Codable {
        case incoming
        case answered
        case ended
        case missed
    }
    public var callState: CallState
    public var callerName: String?
    public var callerNumber: String

    public init(callState: CallState, callerName: String?, callerNumber: String) {
        self.callState = callState
        self.callerName = callerName
        self.callerNumber = callerNumber
    }
}

/// File transfer header packet
public struct FileTransferInitPayload: Codable {
    public var transferId: UUID
    public var fileName: String
    public var fileSize: Int64
    public var mimeType: String
    public var destinationFolder: String

    public init(transferId: UUID = UUID(), fileName: String, fileSize: Int64, mimeType: String, destinationFolder: String = "/sdcard/Download") {
        self.transferId = transferId
        self.fileName = fileName
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.destinationFolder = destinationFolder
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
