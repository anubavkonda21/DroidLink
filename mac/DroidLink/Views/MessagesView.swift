//
//  MessagesView.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import SwiftUI

/// Messages view synchronizing Android SMS/MMS conversations with native macOS styling,
/// real-time incoming call alerts, and inline text composition.
public struct MessagesView: View {
    // MARK: - State

    @Environment(ConnectionManager.self) private var connectionManager
    @State private var conversations: [Conversation] = Conversation.mockConversations
    @State private var selectedConversation: Conversation? = Conversation.mockConversations.first
    @State private var searchContactText: String = ""
    @State private var composeText: String = ""

    // Incoming Call Banner State
    @State private var simulatedIncomingCall: CallEventPayload? = CallEventPayload(
        callState: .incoming,
        callerName: "Sarah Connor",
        callerNumber: "+1 (555) 234-5678"
    )

    public init() {}

    private var filteredConversations: [Conversation] {
        if searchContactText.isEmpty {
            return conversations
        } else {
            return conversations.filter {
                $0.contactName.localizedCaseInsensitiveContains(searchContactText) ||
                $0.contactNumber.contains(searchContactText)
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Incoming Call Banner (if active)
            if let call = simulatedIncomingCall {
                incomingCallBanner(call: call)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Split View: Conversations List (left) + Message Thread (right)
            HSplitView {
                conversationsSidebar
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

                messageThreadView
                    .frame(minWidth: 400, maxWidth: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Incoming Call Banner

    private func incomingCallBanner(call: CallEventPayload) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 44, height: 44)

                Image(systemName: "phone.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Incoming Android Call")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                }

                Text(call.callerName ?? call.callerNumber)
                    .font(.headline)

                Text(call.callerNumber)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Reject Button
            Button(role: .destructive) {
                withAnimation {
                    simulatedIncomingCall = nil
                }
            } label: {
                Label("Decline", systemImage: "phone.down.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)

            // Accept Button
            Button {
                withAnimation {
                    simulatedIncomingCall = nil
                }
            } label: {
                Label("Accept", systemImage: "phone.fill")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.gray.opacity(0.2)), alignment: .bottom)
    }

    // MARK: - Conversations Sidebar

    private var conversationsSidebar: some View {
        VStack(spacing: 0) {
            // Search & New Message Header
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search", text: $searchContactText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    // Start new conversation modal
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(14)

            Divider()

            // List of Conversations
            List(filteredConversations, selection: $selectedConversation) { conv in
                conversationRow(conv: conv)
                    .tag(conv)
            }
            .listStyle(.sidebar)
        }
    }

    private func conversationRow(conv: Conversation) -> some View {
        HStack(spacing: 12) {
            // Initials Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.85))
                    .frame(width: 38, height: 38)

                Text(conv.initials)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conv.contactName)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    Spacer()
                    if let last = conv.lastMessage {
                        Text(last.formattedTime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if let last = conv.lastMessage {
                    Text(last.body)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if conv.unreadCount > 0 {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Message Thread View

    private var messageThreadView: some View {
        VStack(spacing: 0) {
            if let conversation = selectedConversation {
                // Thread Header
                threadHeader(conversation: conversation)

                Divider()

                // Messages Bubble Scroll
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(conversation.messages) { message in
                                messageBubble(message: message)
                                    .id(message.id)
                            }
                        }
                        .padding(20)
                    }
                    .onChange(of: conversation.messages.count) { _, _ in
                        if let lastId = conversation.messages.last?.id {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Message Input Field
                inputBar(for: conversation)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text("Select a conversation to start messaging")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    private func threadHeader(conversation: Conversation) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.contactName)
                    .font(.headline)
                Text(conversation.contactNumber)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                // Call via device
            } label: {
                Image(systemName: "phone.fill")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Message Bubble

    private func messageBubble(message: Message) -> some View {
        HStack {
            if !message.isIncoming {
                Spacer(minLength: 50)
            }

            VStack(alignment: message.isIncoming ? .leading : .trailing, spacing: 4) {
                Text(message.body)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(message.isIncoming ? Color.primary : Color.white)
                    .background(
                        message.isIncoming ?
                            Color(NSColor.controlBackgroundColor) :
                            Color.blue,
                        in: RoundedRectangle(cornerRadius: 16)
                    )

                Text(message.formattedTime)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if message.isIncoming {
                Spacer(minLength: 50)
            }
        }
    }

    // MARK: - Input Bar

    private func inputBar(for conversation: Conversation) -> some View {
        HStack(spacing: 12) {
            TextField("iMessage / SMS...", text: $composeText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                .onSubmit {
                    sendMessage(in: conversation)
                }

            Button {
                sendMessage(in: conversation)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .disabled(composeText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func sendMessage(in conversation: Conversation) {
        let text = composeText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        let newMsg = Message(
            conversationId: conversation.id,
            contactName: conversation.contactName,
            contactNumber: conversation.contactNumber,
            body: text,
            timestamp: Date(),
            isIncoming: false
        )

        if let idx = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[idx].messages.append(newMsg)
            selectedConversation = conversations[idx]
        }

        // Send SMS payload to Android device
        connectionManager.sendControlMessage(
            type: .smsSend,
            payload: SendSMSPayload(recipientNumber: conversation.contactNumber, messageBody: text)
        )

        composeText = ""
    }
}
