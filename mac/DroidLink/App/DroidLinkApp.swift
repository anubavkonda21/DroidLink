//
//  DroidLinkApp.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import SwiftUI

/// Main entry point for the DroidLink macOS application.
@main
struct DroidLinkApp: App {
    // MARK: - App Delegate Adaptor

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Shared State

    @State private var connectionManager = ConnectionManager.shared

    // MARK: - Scene Hierarchy

    var body: some Scene {
        // Main Application Window
        WindowGroup {
            ContentView()
                .environment(connectionManager)
                .frame(minWidth: 850, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 750)

        // Settings / Preferences Window (Cmd + ,)
        Settings {
            SettingsView()
                .environment(connectionManager)
        }

        // Persistent Menu Bar Status Item
        MenuBarExtra {
            menuBarContent
        } label: {
            menuBarLabel
        }
    }

    // MARK: - Menu Bar Label

    private var menuBarLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.horizontal.fill")

            if let info = connectionManager.currentDeviceInfo, connectionManager.status.isConnectedOrMirroring {
                Text("\(info.batteryLevel)%")
                    .font(.caption2.monospacedDigit())
            }
        }
    }

    // MARK: - Menu Bar Dropdown Items

    @ViewBuilder
    private var menuBarContent: some View {
        if let info = connectionManager.currentDeviceInfo, connectionManager.status.isConnectedOrMirroring {
            // Device Info Header
            Section {
                Label(info.name, systemImage: "smartphone")
                Label("Battery: \(info.batteryFormatted) (\(info.isCharging ? "Charging" : "Discharging"))", systemImage: info.batterySymbolName)
                Label("Latency: \(connectionManager.latencyMs)ms", systemImage: "speedometer")
            }

            Divider()

            // Quick Actions
            Section {
                Button {
                    // Bring main window to front
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Open DroidLink Window", systemImage: "macwindow")
                }

                if let lastClipboard = connectionManager.clipboardSync.lastCopiedItem {
                    Button {
                        lastClipboard.copyToPasteboard()
                    } label: {
                        Label("Copy: \(lastClipboard.content.displayText.prefix(20))...", systemImage: "doc.on.clipboard")
                    }
                }

                Button {
                    connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .home))
                } label: {
                    Label("Phone Home Button", systemImage: "house")
                }
            }

            Divider()

            // Disconnect Action
            Button {
                connectionManager.disconnect()
            } label: {
                Label("Disconnect \(info.name)", systemImage: "cable.connector.slash")
            }
        } else {
            // Disconnected State
            Text("No Device Connected")

            Divider()

            Button {
                if let first = connectionManager.deviceDiscovery.discoveredDevices.first {
                    connectionManager.connect(to: first)
                } else {
                    connectionManager.simulateMockConnection()
                }
            } label: {
                Label("Connect Device", systemImage: "bolt.fill")
            }

            Button {
                connectionManager.adbService.refreshDevices()
            } label: {
                Label("Refresh Devices", systemImage: "arrow.clockwise")
            }
        }

        Divider()

        // Settings Shortcut
        SettingsLink {
            Text("Settings...")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        // Quit Action
        Button("Quit DroidLink") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
