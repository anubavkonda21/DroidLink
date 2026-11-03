//
//  OnboardingView.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import SwiftUI

/// Interactive onboarding wizard guiding users through developer options,
/// USB debugging setup, companion app pairing, and permission grants.
public struct OnboardingView: View {
    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @Environment(ConnectionManager.self) private var connectionManager
    @State private var currentStepIndex: Int = 0

    // MARK: - Onboarding Steps

    public enum Step: Int, CaseIterable {
        case welcome = 0
        case enableDebugging = 1
        case installCompanion = 2
        case connectDevice = 3
        case grantPermissions = 4
        case ready = 5

        public var title: String {
            switch self {
            case .welcome: return "Welcome to DroidLink"
            case .enableDebugging: return "Enable USB Debugging"
            case .installCompanion: return "Install Companion App"
            case .connectDevice: return "Connect Your Device"
            case .grantPermissions: return "Grant Permissions"
            case .ready: return "You're All Set!"
            }
        }

        public var iconName: String {
            switch self {
            case .welcome: return "sparkles"
            case .enableDebugging: return "hammer.fill"
            case .installCompanion: return "arrow.down.app.fill"
            case .connectDevice: return "cable.connector"
            case .grantPermissions: return "hand.raised.fill"
            case .ready: return "checkmark.seal.fill"
            }
        }
    }

    public init() {}

    private var currentStep: Step {
        Step(rawValue: currentStepIndex) ?? .welcome
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Step Progress Bar
            stepProgressIndicator
                .padding(.top, 24)
                .padding(.horizontal, 30)

            Spacer()

            // Step Content View
            stepContentView
                .padding(30)
                .frame(maxWidth: 500)

            Spacer()

            Divider()

            // Navigation Footer
            navigationFooter
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 620, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Step Progress Indicator

    private var stepProgressIndicator: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { step in
                    Capsule()
                        .fill(step.rawValue <= currentStepIndex ? Color.blue : Color.gray.opacity(0.3))
                        .frame(height: 5)
                }
            }

            Text("Step \(currentStepIndex + 1) of \(Step.allCases.count): \(currentStep.title)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Step Content View

    @ViewBuilder
    private var stepContentView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: currentStep.iconName)
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
            }

            Text(currentStep.title)
                .font(.title2.bold())

            switch currentStep {
            case .welcome:
                welcomeContent
            case .enableDebugging:
                enableDebuggingContent
            case .installCompanion:
                installCompanionContent
            case .connectDevice:
                connectDeviceContent
            case .grantPermissions:
                grantPermissionsContent
            case .ready:
                readyContent
            }
        }
        .multilineTextAlignment(.center)
    }

    // MARK: - Step Pages

    private var welcomeContent: some View {
        Text("DroidLink turns your Mac into the ultimate desktop extension for your Android phone. Mirror at ultra-low latency, sync clipboard seamlessly, receive notifications, and drag & drop files effortlessly.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineSpacing(4)
    }

    private var enableDebuggingContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            bullet(number: "1", text: "Open Android **Settings** → **About Phone**.")
            bullet(number: "2", text: "Tap **Build Number** 7 times until Developer Mode is unlocked.")
            bullet(number: "3", text: "Go to **Developer Options** and switch on **USB Debugging**.")
        }
        .font(.subheadline)
        .padding(.horizontal, 20)
    }

    private var installCompanionContent: some View {
        VStack(spacing: 12) {
            Text("For advanced background audio routing, SMS sync, and notification replies, install the optional DroidLink Companion APK.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    // Quick push APK to connected device if available
                    _ = try? await connectionManager.adbService.executeADB(["install", "-r", "DroidLinkCompanion.apk"])
                }
            } label: {
                Label("Auto-Install Companion via ADB", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var connectDeviceContent: some View {
        VStack(spacing: 14) {
            Text("Plug in your Android phone using a USB-C or Lightning-to-USB cable. When prompted on your phone, check **Always allow from this computer** and tap **Allow**.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if connectionManager.adbService.devices.contains(where: { $0.state == .device }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Device detected and authorized!")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Waiting for USB connection...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var grantPermissionsContent: some View {
        VStack(spacing: 10) {
            Text("On your phone, open the DroidLink Companion app and grant:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                bullet(number: "•", text: "**Notification Access** (to mirror notifications)")
                bullet(number: "•", text: "**SMS & Contacts** (for messaging sync)")
                bullet(number: "•", text: "**Audio Capture** (for system audio playback)")
            }
            .font(.caption)
        }
    }

    private var readyContent: some View {
        VStack(spacing: 10) {
            Text("Your setup is complete! You can now start screen mirroring, copy/paste across devices, and manage phone notifications directly from macOS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func bullet(number: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number)
                .font(.caption.bold())
                .foregroundStyle(.blue)
                .frame(width: 18)
            Text(text)
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    // MARK: - Navigation Footer

    private var navigationFooter: some View {
        HStack {
            if currentStepIndex > 0 {
                Button("Back") {
                    withAnimation {
                        currentStepIndex -= 1
                    }
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if currentStepIndex < Step.allCases.count - 1 {
                Button("Continue") {
                    withAnimation {
                        currentStepIndex += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Get Started") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
