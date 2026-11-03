//
//  SettingsView.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import SwiftUI

/// Preferences & Settings view containing configuration tabs for stream quality,
/// system integration, clipboard automation, and notification bridges.
public struct SettingsView: View {
    // MARK: - AppStorage Bindings

    @AppStorage(MirrorSettings.StorageKeys.autoConnect) private var autoConnect: Bool = true
    @AppStorage(MirrorSettings.StorageKeys.launchAtLogin) private var launchAtLogin: Bool = false
    @AppStorage(MirrorSettings.StorageKeys.preferredConnection) private var preferredConnection: String = "USB"

    @AppStorage(MirrorSettings.StorageKeys.maxResolution) private var maxResolution: String = ResolutionOption.native.rawValue
    @AppStorage(MirrorSettings.StorageKeys.maxFps) private var maxFps: Double = 60.0
    @AppStorage(MirrorSettings.StorageKeys.codec) private var codec: String = VideoCodec.h264.rawValue
    @AppStorage(MirrorSettings.StorageKeys.bitrateMbps) private var bitrateMbps: Double = 12.0
    @AppStorage(MirrorSettings.StorageKeys.audioEnabled) private var audioEnabled: Bool = true
    @AppStorage(MirrorSettings.StorageKeys.turnScreenOff) private var turnScreenOff: Bool = false

    @AppStorage(MirrorSettings.StorageKeys.autoSyncClipboard) private var autoSyncClipboard: Bool = true
    @AppStorage(MirrorSettings.StorageKeys.otpAutoForward) private var otpAutoForward: Bool = true
    @AppStorage(MirrorSettings.StorageKeys.clipboardHistoryCount) private var clipboardHistoryCount: Int = 25

    @AppStorage(MirrorSettings.StorageKeys.enableNotifications) private var enableNotifications: Bool = true
    @AppStorage(MirrorSettings.StorageKeys.notificationSound) private var notificationSound: Bool = true
    @AppStorage(MirrorSettings.StorageKeys.syncDnd) private var syncDnd: Bool = true

    @AppStorage(MirrorSettings.StorageKeys.downloadDirectory) private var downloadDirectory: String = ""
    @AppStorage(MirrorSettings.StorageKeys.autoOrganizeFiles) private var autoOrganizeFiles: Bool = true

    public init() {}

    public var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            mirrorTab
                .tabItem {
                    Label("Mirroring", systemImage: "display")
                }

            clipboardTab
                .tabItem {
                    Label("Clipboard", systemImage: "doc.on.clipboard")
                }

            notificationsTab
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }

            fileTransferTab
                .tabItem {
                    Label("Files", systemImage: "folder")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 580, height: 440)
        .padding(20)
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section {
                Toggle("Auto-connect to previously paired devices", isOn: $autoConnect)
                Toggle("Launch DroidLink at macOS login", isOn: $launchAtLogin)
            } header: {
                Text("Startup & Connectivity")
            }

            Section {
                Picker("Preferred Connection", selection: $preferredConnection) {
                    Text("USB Cable (Lowest Latency)").tag("USB")
                    Text("Wi-Fi (Wireless)").tag("Wi-Fi")
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("Connection Preference")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Mirroring Tab

    private var mirrorTab: some View {
        Form {
            Section {
                Picker("Stream Resolution", selection: $maxResolution) {
                    ForEach(ResolutionOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt.rawValue)
                    }
                }

                Picker("Video Codec", selection: $codec) {
                    ForEach(VideoCodec.allCases) { c in
                        Text(c.rawValue).tag(c.rawValue)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Maximum Frame Rate")
                        Spacer()
                        Text("\(Int(maxFps)) FPS")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $maxFps, in: 30...120, step: 15)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Bitrate Limit")
                        Spacer()
                        Text("\(Int(bitrateMbps)) Mbps")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $bitrateMbps, in: 2...30, step: 2)
                }
            } header: {
                Text("Video Quality")
            }

            Section {
                Toggle("Forward Android Audio to Mac speakers", isOn: $audioEnabled)
                Toggle("Turn off Android screen while mirroring (Saves battery)", isOn: $turnScreenOff)
            } header: {
                Text("Display & Audio")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Clipboard Tab

    private var clipboardTab: some View {
        Form {
            Section {
                Toggle("Bidirectional Clipboard Sync", isOn: $autoSyncClipboard)
                Toggle("Auto-detect and highlight OTP verification codes", isOn: $otpAutoForward)
            } header: {
                Text("Synchronization")
            }

            Section {
                Stepper("Clipboard History Retention: \(clipboardHistoryCount) items", value: $clipboardHistoryCount, in: 5...100, step: 5)
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Notifications Tab

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("Receive Android notifications on Mac", isOn: $enableNotifications)
                Toggle("Play sound for incoming alerts", isOn: $notificationSound)
                Toggle("Mirror macOS Focus / Do Not Disturb state", isOn: $syncDnd)
            } header: {
                Text("Alerts")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - File Transfer Tab

    private var fileTransferTab: some View {
        Form {
            Section {
                HStack {
                    Text("Download Location")
                    Spacer()
                    Text(downloadDirectory.isEmpty ? "Downloads" : (downloadDirectory as NSString).lastPathComponent)
                        .foregroundStyle(.secondary)
                    Button("Browse...") {
                        selectDownloadDirectory()
                    }
                }

                Toggle("Auto-organize files by type (Pictures, Music, Documents)", isOn: $autoOrganizeFiles)
            } header: {
                Text("Storage")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - About Tab

    private var aboutTab: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)

                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text("DroidLink for macOS")
                    .font(.title2.bold())
                Text("Version 1.0.0 (Build 2026.11)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Next-generation Android screen mirroring and seamless Apple-like ecosystem continuity for macOS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            HStack(spacing: 16) {
                Link("GitHub Repository", destination: URL(string: "https://github.com/droidlink")!)
                Link("Documentation", destination: URL(string: "https://droidlink.app/docs")!)
            }
            .font(.caption.bold())

            Spacer()

            Text("Copyright © 2026 DroidLink Team. Open source under Apache 2.0.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private func selectDownloadDirectory() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                downloadDirectory = url.path
            }
        }
    }
}
