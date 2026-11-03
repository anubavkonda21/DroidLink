//
//  OnboardingWindowController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

/// Wizard window controller guiding users through Android device setup.
public final class OnboardingWindowController: NSWindowController {
    public static let shared = OnboardingWindowController()

    public init() {
        let contentVC = OnboardingViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DroidLink Setup Wizard"
        window.contentViewController = contentVC
        window.center()
        super.init(window: window)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showWizard() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

public final class OnboardingViewController: NSViewController {
    private var currentStep = 0
    private let totalSteps = 6

    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var iconView: NSImageView!
    private var instructionTextView: NSTextView!
    private var progressIndicator: NSProgressIndicator!
    private var stepLabel: NSTextField!

    private var backButton: NSButton!
    private var nextButton: NSButton!

    private struct StepInfo {
        let title: String
        let icon: String
        let text: String
    }

    private let steps: [StepInfo] = [
        StepInfo(
            title: "Welcome to DroidLink",
            icon: "sparkles",
            text: "DroidLink brings your Android experience seamlessly to macOS with ultra-low latency screen mirroring, notification forwarding, clipboard synchronization, and high-speed wireless file transfers.\n\nLet's get your device configured in just a few quick steps!"
        ),
        StepInfo(
            title: "Enable Developer Options & USB Debugging",
            icon: "hammer.fill",
            text: "1. On your Android phone, open Settings > About Phone.\n2. Tap 'Build Number' 7 times until you see 'You are now a developer!'.\n3. Go back to Settings > System > Developer Options.\n4. Enable 'USB Debugging'.\n5. (Recommended) Enable 'Stay Awake' and 'Disable ADB authorization timeout'."
        ),
        StepInfo(
            title: "Install the Companion App",
            icon: "arrow.down.app.fill",
            text: "DroidLink requires a lightweight companion service running on your Android device to forward notifications, clipboard contents, and system audio.\n\nConnect via USB to install automatically, or sideload 'DroidLink-Companion.apk' onto your phone."
        ),
        StepInfo(
            title: "Connect Your Device",
            icon: "cable.connector",
            text: "Plug your Android device into your Mac using a certified USB cable.\n\nWhen prompted on your phone screen:\n1. Check 'Always allow from this computer'.\n2. Tap 'Allow' or 'OK'.\n\nDroidLink will automatically detect the device and negotiate local port forwarding."
        ),
        StepInfo(
            title: "Grant Android Permissions",
            icon: "hand.raised.fill",
            text: "On your phone's companion app, tap to approve:\n\n• Notification Listener: Required to display Android notifications on Mac\n• Media Projection (Screen Capture): Required for screen mirroring\n• Accessibility / Input: Required to control the phone via mouse and keyboard"
        ),
        StepInfo(
            title: "You're All Set!",
            icon: "checkmark.seal.fill",
            text: "Setup is complete!\n\nYou can now mirror your Android screen at up to 60 FPS, sync your clipboard bidirectionally, receive notifications, and drag & drop files between macOS and Android.\n\nClick 'Get Started' to begin."
        )
    ]

    public override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 480))
        self.view = container

        // Progress bar at top
        progressIndicator = NSProgressIndicator()
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = Double(totalSteps)
        progressIndicator.doubleValue = 1.0
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(progressIndicator)

        stepLabel = NSTextField(labelWithString: "Step 1 of \(totalSteps)")
        stepLabel.font = .systemFont(ofSize: 11, weight: .medium)
        stepLabel.textColor = .secondaryLabelColor
        stepLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stepLabel)

        // Icon
        iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Step Icon")
        iconView.contentTintColor = .systemBlue
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)

        // Title
        titleLabel = NSTextField(labelWithString: "Welcome to DroidLink")
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

        // Instructions text scroll view
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        instructionTextView = NSTextView()
        instructionTextView.isEditable = false
        instructionTextView.isSelectable = true
        instructionTextView.font = .systemFont(ofSize: 13)
        instructionTextView.textColor = .labelColor
        instructionTextView.drawsBackground = false
        scroll.documentView = instructionTextView
        container.addSubview(scroll)

        // Bottom separator
        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sep)

        // Bottom buttons
        backButton = NSButton(title: "Previous", target: self, action: #selector(backClicked(_:)))
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.isEnabled = false
        container.addSubview(backButton)

        nextButton = NSButton(title: "Continue", target: self, action: #selector(nextClicked(_:)))
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nextButton)

        NSLayoutConstraint.activate([
            progressIndicator.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            progressIndicator.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            progressIndicator.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),
            progressIndicator.heightAnchor.constraint(equalToConstant: 6),

            stepLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 6),
            stepLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),

            iconView.topAnchor.constraint(equalTo: stepLabel.bottomAnchor, constant: 16),
            iconView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            iconView.widthAnchor.constraint(equalToConstant: 44),
            iconView.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),

            scroll.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 20),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),
            scroll.bottomAnchor.constraint(equalTo: sep.topAnchor, constant: -16),

            sep.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -56),
            sep.heightAnchor.constraint(equalToConstant: 1),

            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            backButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            backButton.widthAnchor.constraint(equalToConstant: 90),

            nextButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            nextButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),
            nextButton.widthAnchor.constraint(equalToConstant: 110)
        ])

        updateStepUI()
    }

    private func updateStepUI() {
        guard currentStep >= 0 && currentStep < steps.count else { return }
        let step = steps[currentStep]

        titleLabel.stringValue = step.title
        iconView.image = NSImage(systemSymbolName: step.icon, accessibilityDescription: step.title)
        instructionTextView.string = step.text
        stepLabel.stringValue = "Step \(currentStep + 1) of \(totalSteps)"
        progressIndicator.doubleValue = Double(currentStep + 1)

        backButton.isEnabled = currentStep > 0
        if currentStep == totalSteps - 1 {
            nextButton.title = "Get Started"
        } else {
            nextButton.title = "Continue"
        }
    }

    @objc private func backClicked(_ sender: NSButton) {
        if currentStep > 0 {
            currentStep -= 1
            updateStepUI()
        }
    }

    @objc private func nextClicked(_ sender: NSButton) {
        if currentStep < totalSteps - 1 {
            currentStep += 1
            updateStepUI()
        } else {
            // Finished
            view.window?.close()
        }
    }
}
