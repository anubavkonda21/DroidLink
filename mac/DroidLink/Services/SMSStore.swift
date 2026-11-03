//
//  SMSStore.swift
//  DroidLink
//
//  Holds the phone's SMS conversations for the Messages page.
//  The phone sends "sms_list" when asked and again whenever a text arrives or is sent.
//

import Foundation

/// Payload of "sms_list" from the phone.
public struct SMSListPayload: Codable {
    public struct Thread: Codable {
        public var threadId: String
        public var contactName: String?
        public var contactNumber: String
        public var unreadCount: Int?
        public var messages: [Item]
    }
    public struct Item: Codable {
        public var id: String
        public var body: String
        public var timestamp: Double   // seconds since 1970
        public var isIncoming: Bool
        public var isRead: Bool?
        public var status: String?     // delivered | pending | failed
    }
    public var permissionMissing: Bool?
    public var canSend: Bool?
    public var conversations: [Thread]
}

/// Mac -> phone: "send me the conversation list".
public struct SMSListRequest: Codable {
    public var limit: Int = 80
}

public final class SMSStore {
    public static let shared = SMSStore()
    public static let didChangeNotification = Notification.Name("SMSStoreDidChange")

    public enum State: Equatable {
        case idle          // never asked
        case loading
        case loaded
        case permissionMissing
    }

    public private(set) var conversations: [Conversation] = []
    public private(set) var state: State = .idle
    public private(set) var canSend = true

    /// Messages typed on the Mac that the phone hasn't confirmed yet, by number.
    private var pending: [String: [Message]] = [:]

    private init() {}

    /// Asks the phone for its conversations. Safe to call often.
    public func refresh() {
        guard ConnectionManager.shared.status.isConnectedOrMirroring else { return }
        if state != .loaded { setState(.loading) }
        ConnectionManager.shared.sendControlMessage(type: .smsList, payload: SMSListRequest())
        // if the phone app is older and never answers, stop spinning
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            if self?.state == .loading { self?.setState(.idle) }
        }
    }

    public func send(_ text: String, to conversation: Conversation) {
        let msg = Message(conversationId: conversation.id, contactName: conversation.contactName,
                          contactNumber: conversation.contactNumber, body: text, timestamp: Date(),
                          isIncoming: false, deliveryStatus: .pending)
        pending[conversation.contactNumber, default: []].append(msg)
        if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[i].messages.append(msg)
            let c = conversations.remove(at: i)
            conversations.insert(c, at: 0)
        }
        post()
        ConnectionManager.shared.sendControlMessage(
            type: .smsSend, payload: SendSMSPayload(recipientNumber: conversation.contactNumber, messageBody: text))
    }

    /// Called on the network queue with the phone's list.
    func apply(_ payload: SMSListPayload) {
        DispatchQueue.main.async {
            self.canSend = payload.canSend ?? true
            if payload.permissionMissing == true {
                self.conversations = []
                self.setState(.permissionMissing)
                return
            }
            self.conversations = payload.conversations.map { t in
                let name = (t.contactName?.isEmpty == false) ? t.contactName! : t.contactNumber
                var messages = t.messages.map { m in
                    Message(conversationId: t.contactNumber, contactName: name, contactNumber: t.contactNumber,
                            body: m.body, timestamp: Date(timeIntervalSince1970: m.timestamp),
                            isIncoming: m.isIncoming, isRead: m.isRead ?? true,
                            deliveryStatus: m.status == "failed" ? .failed : (m.status == "pending" ? .pending : .delivered))
                }
                // keep Mac-typed texts visible until the phone's copy shows up
                if var mine = self.pending[t.contactNumber] {
                    mine.removeAll { p in messages.contains { !$0.isIncoming && $0.body == p.body && abs($0.timestamp.timeIntervalSince(p.timestamp)) < 300 } }
                    mine.removeAll { Date().timeIntervalSince($0.timestamp) > 300 }
                    self.pending[t.contactNumber] = mine.isEmpty ? nil : mine
                    messages += mine
                }
                return Conversation(contactName: name, contactNumber: t.contactNumber,
                                    messages: messages, unreadCount: t.unreadCount ?? 0)
            }
            self.setState(.loaded)
        }
    }

    private func setState(_ s: State) {
        state = s
        post()
    }

    private func post() {
        NotificationCenter.default.post(name: SMSStore.didChangeNotification, object: self)
    }
}
