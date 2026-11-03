//
//  ContentView.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import SwiftUI

/// Root content navigation container utilizing macOS NavigationSplitView.
public struct ContentView: View {
    // MARK: - Navigation Items

    public enum NavigationItem: String, CaseIterable, Identifiable {
        case mirror = "Mirror"
        case dashboard = "Dashboard"
        case notifications = "Notifications"
        case files = "Files"
        case messages = "Messages"
        case settings = "Settings"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .mirror: return "display"
            case .dashboard: return "gauge.with.needle"
            case .notifications: return "bell"
            case .files: return "folder"
            case .messages: return "message"
            case .settings: return "gear"
            }
        }
    }

    // MARK: - State

    @Environment(ConnectionManager.self) private var connectionManager
    @State private var selectedItem: NavigationItem? = .mirror
    @State private var showingOnboardingSheet: Bool = false

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailContent
        }
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showingOnboardingSheet) {
            OnboardingView()
        }
    }

    // MARK: - Sidebar

    private var sidebarContent: some View {
        List(NavigationItem.allCases, selection: $selectedItem) { item in
            NavigationLink(value: item) {
                HStack(spacing: 10) {
                    Image(systemName: item.iconName)
                        .font(.system(size: 14))
                        .foregroundStyle(selectedItem == item ? Color.accentColor : Color.secondary)
                        .frame(width: 20)

                    Text(item.rawValue)
                        .font(.body)

                    Spacer()

                    // Notification & File badges
                    if item == .notifications {
                        let count = connectionManager.notificationBridge.notifications.filter { !$0.isRead }.count
                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    } else if item == .files {
                        let activeCount = connectionManager.fileTransferService.activeTransfers.count
                        if activeCount > 0 {
                            Text("\(activeCount)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    private var sidebarFooter: some View {
        VStack(spacing: 8) {
            Divider()
            Button {
                showingOnboardingSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                    Text("Setup Guide & Wizard")
                    Spacer()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Detail Content

    @ViewBuilder
    private var detailContent: some View {
        switch selectedItem {
        case .mirror:
            MirrorView()
        case .dashboard:
            DashboardView()
        case .notifications:
            NotificationPanel()
        case .files:
            FileTransferView()
        case .messages:
            MessagesView()
        case .settings:
            SettingsView()
        case .none:
            MirrorView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            // Connection Status Pill
            HStack(spacing: 8) {
                Circle()
                    .fill(statusIndicatorColor)
                    .frame(width: 8, height: 8)

                if let info = connectionManager.currentDeviceInfo {
                    Text(info.name)
                        .font(.subheadline.bold())

                    HStack(spacing: 2) {
                        Image(systemName: info.batterySymbolName)
                        Text(info.batteryFormatted)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else {
                    Text(connectionManager.status.statusTitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor), in: Capsule())
        }

        ToolbarItem(placement: .primaryAction) {
            // Connect / Disconnect Toggle Button
            if connectionManager.status.isConnectedOrMirroring {
                Button {
                    connectionManager.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "cable.connector.slash")
                }
                .help("Disconnect from Android device")
            } else {
                Button {
                    if let first = connectionManager.deviceDiscovery.discoveredDevices.first {
                        connectionManager.connect(to: first)
                    } else {
                        connectionManager.simulateMockConnection()
                    }
                } label: {
                    Label("Connect", systemImage: "bolt.fill")
                }
                .buttonStyle(.borderedProminent)
                .help("Connect to device")
            }
        }
    }

    private var statusIndicatorColor: Color {
        switch connectionManager.status {
        case .mirroring, .connected:
            return .green
        case .connecting, .reconnecting, .discovering:
            return .orange
        case .disconnected, .error:
            return .red
        }
    }
}
