//
//  NotificationPanel.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import SwiftUI

/// Notification panel displaying incoming synchronized notifications from Android,
/// with app filtering, search, inline quick-reply, and individual dismiss capabilities.
public struct NotificationPanel: View {
    // MARK: - Environment & State

    @Environment(ConnectionManager.self) private var connectionManager
    @State private var selectedAppFilter: String = "All"
    @State private var searchQuery: String = ""
    @State private var inlineReplyText: [String: String] = [:]

    public init() {}

    private var bridge: NotificationBridge {
        connectionManager.notificationBridge
    }

    private var availableApps: [String] {
        var set = Set(bridge.notifications.map { $0.appName })
        return ["All"] + Array(set).sorted()
    }

    private var filteredNotifications: [AndroidNotification] {
        bridge.notifications.filter { item in
            let matchesApp = (selectedAppFilter == "All") || (item.appName == selectedAppFilter)
            let matchesSearch = searchQuery.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchQuery) ||
                item.body.localizedCaseInsensitiveContains(searchQuery) ||
                item.appName.localizedCaseInsensitiveContains(searchQuery)
            return matchesApp && matchesSearch
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Filter & Search Header
            filterHeader
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Notifications List / Empty State
            if filteredNotifications.isEmpty {
                emptyState
            } else {
                notificationsList
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header Controls

    private var filterHeader: some View {
        HStack(spacing: 14) {
            // Search Input Field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search notifications...", text: $searchQuery)
                    .textFieldStyle(.plain)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2), lineWidth: 1))

            // App Filter Picker
            Picker("App", selection: $selectedAppFilter) {
                ForEach(availableApps, id: \.self) { app in
                    Text(app).tag(app)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 130)

            Spacer()

            // Clear All Button
            Button(role: .destructive) {
                bridge.clearAll()
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(bridge.notifications.isEmpty)
        }
    }

    // MARK: - Notifications List

    private var notificationsList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredNotifications) { item in
                    notificationCard(item: item)
                }
            }
            .padding(20)
        }
    }

    // MARK: - Single Notification Card

    private func notificationCard(item: AndroidNotification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Card Header
            HStack(spacing: 10) {
                // App Icon Placeholder / SF Symbol
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 28, height: 28)

                    Image(systemName: item.fallbackSymbolName)
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }

                Text(item.appName)
                    .font(.subheadline.bold())

                Spacer()

                Text(item.relativeTimeFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                // Dismiss Button
                Button {
                    withAnimation {
                        bridge.dismissNotification(id: item.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Notification Title & Body
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))

                Text(item.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            // Inline Reply Field (if supported by app, e.g. WhatsApp / Slack / Messages)
            if item.canReply {
                HStack(spacing: 8) {
                    TextField(
                        "Reply to \(item.title)...",
                        text: Binding(
                            get: { inlineReplyText[item.id] ?? "" },
                            set: { inlineReplyText[item.id] = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitReply(for: item)
                    }

                    Button {
                        submitReply(for: item)
                    } label: {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled((inlineReplyText[item.id] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.top, 4)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(item.isRead ? Color.clear : Color.blue.opacity(0.3), lineWidth: 1)
        )
    }

    private func submitReply(for item: AndroidNotification) {
        let text = inlineReplyText[item.id] ?? ""
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        bridge.sendReply(notificationId: item.id, replyText: text)
        inlineReplyText[item.id] = ""
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bell.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("No Notifications")
                    .font(.headline)

                Text("You're all caught up. When Android notifications arrive, they will appear here in real-time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }

            Spacer()
        }
        .padding()
    }
}
