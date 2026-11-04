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
        window.title = "DroidLink Setup Guide"
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
    private var totalSteps: Int { steps.count }

    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var iconView: NSImageView!
    private var instructionTextView: NSTextView!
    private var progressIndicator: NSProgressIndicator!
    private var stepLabel: NSTextField!

    private var backButton: NSButton!
    private var nextButton: NSButton!
    private var actionButton: NSButton!

    private struct StepInfo {
        let title: String
        let icon: String
        let text: String
        var button: String? = nil // optional extra action shown in the bottom bar
    }

    private let steps: [StepInfo] = [
        StepInfo(
            title: "Welcome to DroidLink",
            icon: "bolt.horizontal.fill",
            text: "DroidLink links your Android phone to this Mac over Wi-Fi, no cable needed.\n\n• See and control your phone in a window\n• Get phone notifications, calls and texts on the Mac\n• Share the clipboard and send files both ways\n• Use the phone as a webcam\n\nSetup takes about two minutes."
        ),
        StepInfo(
            title: "Turn On Wireless Debugging",
            icon: "wrench.and.screwdriver.fill",
            text: "On your phone:\n\n1. Open Settings › About phone and tap Build number 7 times, until it says you're a developer.\n2. Go to Settings › System › Developer options.\n3. Turn on Wireless debugging and tap Allow.\n\nThe phone and the Mac must be on the same Wi-Fi for this first pairing."
        ),
        StepInfo(
            title: "Pair With a QR Code",
            icon: "qrcode",
            text: "1. Click Show QR Code below. A pairing code opens on the Mac.\n2. On the phone, in Wireless debugging, tap Pair device with QR code.\n3. Point the phone at the code on the Mac.\n\nThat's it. DroidLink remembers the phone and reconnects on its own next time, even after a restart. You can also add phones later from the bolt icon in the menu bar › Add Phone with QR Code.",
            button: "Show QR Code"
        ),
        StepInfo(
            title: "Open the Phone App",
            icon: "iphone.gen3",
            text: "Open the DroidLink app on the phone and allow what it asks for:\n\n• Notification access, so notifications appear on the Mac\n• Phone, contacts and SMS, so calls and texts show up\n• Files and photos, so you can send them to the Mac\n\nWhen it says Connected, you're linked."
        ),
        StepInfo(
            title: "You're All Set",
            icon: "checkmark.seal.fill",
            text: "Here's where everything lives:\n\n• Dashboard: phone battery, storage and quick actions\n• Mirror: shows and controls your phone screen\n• Notifications, Files and Messages: in the sidebar\n\nAway from home? If both devices are on Tailscale, DroidLink finds the phone there too.\n\nYou can reopen this guide any time with the ? button in the sidebar."
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
        iconView.contentTintColor = .droidAccent
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

        actionButton = NSButton(title: "", target: self, action: #selector(actionClicked(_:)))
        actionButton.bezelStyle = .rounded
        actionButton.bezelColor = .droidAccent
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(actionButton)

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

            actionButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            actionButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16),

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
        actionButton.title = step.button ?? ""
        actionButton.isHidden = step.button == nil
        if currentStep == totalSteps - 1 {
            nextButton.title = "Get Started"
        } else {
            nextButton.title = "Continue"
        }
    }

    @objc private func actionClicked(_ sender: NSButton) {
        AddDeviceWindowController.shared.show()
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
