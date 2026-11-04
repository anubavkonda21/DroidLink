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

/// Mac -> phone: mark a thread read (or its newest text unread) in the phone's SMS store.
public struct SMSMarkReadPayload: Codable {
    public var threadId: String
    public var read: Bool
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
    /// Phone thread id per number, so read/unread can be sent back to the phone.
    private var threadIds: [String: String] = [:]

    // Mac-side chat state, kept across launches. Keys are phone numbers (Conversation.id).
    private let defaults = UserDefaults.standard
    private var readUpTo: [String: Double]      // newest incoming text seen, per chat
    private var manualUnread: Set<String>       // marked unread by the user
    private var pinned: [String]                // in pin order
    private var archived: [String: Double]      // last-message time when archived; a newer text un-archives
    public var showingArchived = false { didSet { post() } }

    private init() {
        readUpTo = defaults.dictionary(forKey: "sms.readUpTo") as? [String: Double] ?? [:]
        manualUnread = Set(defaults.stringArray(forKey: "sms.manualUnread") ?? [])
        pinned = defaults.stringArray(forKey: "sms.pinned") ?? []
        archived = defaults.dictionary(forKey: "sms.archived") as? [String: Double] ?? [:]
    }

    private func save() {
        defaults.set(readUpTo, forKey: "sms.readUpTo")
        defaults.set(Array(manualUnread), forKey: "sms.manualUnread")
        defaults.set(pinned, forKey: "sms.pinned")
        defaults.set(archived, forKey: "sms.archived")
    }

    // MARK: - Chat state (read, pin, archive)

    private func lastIncoming(_ c: Conversation) -> Double {
        c.messages.filter { $0.isIncoming }.map { $0.timestamp.timeIntervalSince1970 }.max() ?? 0
    }

    public func isUnread(_ c: Conversation) -> Bool {
        if manualUnread.contains(c.id) { return true }
        return c.unreadCount > 0 && lastIncoming(c) > (readUpTo[c.id] ?? 0)
    }

    public func isManuallyUnread(_ c: Conversation) -> Bool { manualUnread.contains(c.id) }
    public func isPinned(_ c: Conversation) -> Bool { pinned.contains(c.id) }

    public func isArchived(_ c: Conversation) -> Bool {
        guard let at = archived[c.id] else { return false }
        return (c.lastMessage?.timestamp.timeIntervalSince1970 ?? 0) <= at + 0.5
    }

    public var archivedCount: Int { conversations.filter { isArchived($0) }.count }
    public var unreadCount: Int { conversations.filter { isUnread($0) && !isArchived($0) }.count }

    /// What the list shows: pinned chats first, archived chats only in the Archived view.
    public var visibleConversations: [Conversation] {
        if showingArchived { return conversations.filter { isArchived($0) } }
        let live = conversations.filter { !isArchived($0) }
        let pins = pinned.compactMap { id in live.first { $0.id == id } }
        return pins + live.filter { !pinned.contains($0.id) }
    }

    public func markRead(_ c: Conversation) {
        let was = isUnread(c)
        manualUnread.remove(c.id)
        readUpTo[c.id] = max(readUpTo[c.id] ?? 0, lastIncoming(c))
        if let i = conversations.firstIndex(where: { $0.id == c.id }) { conversations[i].unreadCount = 0 }
        save()
        if was { sendReadState(c, read: true) }
        post()
    }

    public func markUnread(_ c: Conversation) {
        manualUnread.insert(c.id)
        save()
        sendReadState(c, read: false)
        post()
    }

    public func togglePin(_ c: Conversation) {
        if let i = pinned.firstIndex(of: c.id) { pinned.remove(at: i) } else { pinned.append(c.id) }
        save(); post()
    }

    public func toggleArchive(_ c: Conversation) {
        if isArchived(c) {
            archived[c.id] = nil
        } else {
            archived[c.id] = c.lastMessage?.timestamp.timeIntervalSince1970 ?? Date().timeIntervalSince1970
            pinned.removeAll { $0 == c.id }
        }
        if archivedCount == 0 { showingArchived = false }
        save(); post()
    }

    private func sendReadState(_ c: Conversation, read: Bool) {
        guard let tid = threadIds[c.id] else { return }
        ConnectionManager.shared.sendControlMessage(type: .smsMarkRead, payload: SMSMarkReadPayload(threadId: tid, read: read))
    }

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
            for t in payload.conversations { self.threadIds[t.contactNumber] = t.threadId }
            // drop archive marks for chats that got a newer text, so they come back to the list
            for (id, at) in self.archived {
                if let t = payload.conversations.first(where: { $0.contactNumber == id }),
                   let newest = t.messages.map({ $0.timestamp }).max(), newest > at + 0.5 {
                    self.archived[id] = nil
                }
            }
            self.save()
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
