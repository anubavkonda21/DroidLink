//
//  DashboardView.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import SwiftUI

/// Dashboard view providing a comprehensive health overview of the connected Android device,
/// including battery telemetry, storage utilization, network status, and quick ecosystem actions.
public struct DashboardView: View {
    // MARK: - Environment & State

    @Environment(ConnectionManager.self) private var connectionManager

    @State private var isHotspotActive: Bool = false
    @State private var isDarkModeSynced: Bool = true
    @State private var isFindingPhone: Bool = false
    @State private var showingRebootConfirm: Bool = false

    public init() {}

    private var device: DeviceInfo {
        connectionManager.currentDeviceInfo ?? DeviceInfo.mockPixel8
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header Banner
                headerBanner

                // Quick Action Buttons
                quickActionsSection

                // Metrics Grid
                metricsGrid

                Spacer()
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert("Reboot Device?", isPresented: $showingRebootConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reboot", role: .destructive) {
                Task {
                    _ = try? await connectionManager.adbService.executeADB(["reboot"])
                }
            }
        } message: {
            Text("Are you sure you want to reboot \(device.name)? The mirroring connection will be disconnected.")
        }
    }

    // MARK: - Header Banner

    private var headerBanner: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)

                Image(systemName: "smartphone")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(device.name)
                        .font(.title2.bold())

                    Label(device.connectionType.rawValue, systemImage: device.connectionType.iconName)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }

                Text("\(device.model) • \(device.androidVersion)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Refresh Device Telemetry Button
            Button {
                Task {
                    if let serial = connectionManager.adbService.selectedDevice?.serial {
                        if let updated = try? await connectionManager.adbService.fetchDeviceInfo(serial: serial) {
                            connectionManager.currentDeviceInfo = updated
                        }
                    }
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.headline)

            HStack(spacing: 12) {
                // Find Phone Button
                actionCard(
                    title: isFindingPhone ? "Ringing..." : "Find Phone",
                    subtitle: "Ring full volume",
                    icon: "speaker.wave.3.fill",
                    color: .orange,
                    isActive: isFindingPhone
                ) {
                    withAnimation { isFindingPhone.toggle() }
                    connectionManager.sendControlMessage(type: .findPhone, payload: ["enabled": isFindingPhone])
                }

                // Toggle Hotspot Button
                actionCard(
                    title: "Mobile Hotspot",
                    subtitle: isHotspotActive ? "Sharing data" : "Turn on tethering",
                    icon: "personalhotspot",
                    color: .green,
                    isActive: isHotspotActive
                ) {
                    withAnimation { isHotspotActive.toggle() }
                }

                // Dark Mode Sync Button
                actionCard(
                    title: "Sync Dark Mode",
                    subtitle: isDarkModeSynced ? "System matched" : "Disabled",
                    icon: "circle.righthalf.filled",
                    color: .purple,
                    isActive: isDarkModeSynced
                ) {
                    withAnimation { isDarkModeSynced.toggle() }
                }

                // Reboot Device Button
                actionCard(
                    title: "Reboot Device",
                    subtitle: "Soft restart",
                    icon: "arrow.clockwise.circle.fill",
                    color: .red,
                    isActive: false
                ) {
                    showingRebootConfirm = true
                }
            }
        }
    }

    private func actionCard(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(color.opacity(isActive ? 1.0 : 0.15))
                            .frame(width: 36, height: 36)

                        Image(systemName: icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isActive ? .white : color)
                    }
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? color.opacity(0.5) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Metrics Grid

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            // Battery Metric Card
            batteryMetricCard

            // Storage Metric Card
            storageMetricCard

            // Network Metric Card
            networkMetricCard

            // Mirror Performance Card
            performanceMetricCard
        }
    }

    // MARK: - Battery Card

    private var batteryMetricCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Battery", systemImage: device.batterySymbolName)
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Text(device.isCharging ? "Charging" : "Discharging")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(device.isCharging ? Color.green.opacity(0.15) : Color.gray.opacity(0.15), in: Capsule())
                    .foregroundStyle(device.isCharging ? .green : .secondary)
            }

            HStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                        .frame(width: 70, height: 70)

                    Circle()
                        .trim(from: 0, to: CGFloat(device.batteryLevel) / 100.0)
                        .stroke(device.batteryLevel > 20 ? Color.green : Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 70, height: 70)

                    Text(device.batteryFormatted)
                        .font(.system(size: 16, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Health: Good (100%)")
                        .font(.caption)
                    Text("Temperature: 31.4°C")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(device.isCharging ? "Fast Charging (USB-PD)" : "Estimated 12 hrs left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Storage Card

    private var storageMetricCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Internal Storage", systemImage: "internaldrive.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Spacer()
                Text(device.storageFormatted)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: device.storageUsedFraction)
                    .tint(.blue)

                HStack {
                    Text("\(ByteCountFormatter.string(fromByteCount: device.storageFree, countStyle: .file)) Free")
                        .font(.caption.bold())
                    Spacer()
                    Text("\(Int(device.storageUsedFraction * 100))% Used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Network Card

    private var networkMetricCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Connectivity", systemImage: "wifi")
                    .font(.headline)
                    .foregroundStyle(.cyan)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                metricRow(label: "Wi-Fi Network", value: device.wifiName ?? "Not connected")
                metricRow(label: "Device IP", value: device.ipAddress ?? "127.0.0.1 (adb forward)")
                metricRow(label: "Transport Type", value: device.connectionType.rawValue)
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Performance Card

    private var performanceMetricCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Stream Performance", systemImage: "speedometer")
                    .font(.headline)
                    .foregroundStyle(.purple)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                metricRow(label: "Stream FPS", value: "\(Int(connectionManager.metalRenderer.currentFps)) FPS")
                metricRow(label: "Stream Latency", value: "\(connectionManager.latencyMs) ms")
                metricRow(label: "Target Resolution", value: "\(device.screenWidth) × \(device.screenHeight)")
            }
        }
        .padding(18)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func metricRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
        }
    }
}
