//
//  OnboardingWindowController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

/// Wizard window controller guiding users through Android phone notification setup.
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
        var button: String? = nil
    }

    private let steps: [StepInfo] = [
        StepInfo(
            title: "Welcome to DroidLink",
            icon: "bell.badge.fill",
            text: "DroidLink sends your Android phone notifications straight to this Mac.\n\n• See phone notifications as native macOS banners\n• Reply to messages right from a notification or this window\n• Dismiss notifications on your Mac to clear them on your phone\n• Choose which phone apps are allowed to notify on your Mac\n\nSetup takes about two minutes."
        ),
        StepInfo(
            title: "Turn On Wireless Debugging",
            icon: "wrench.and.screwdriver.fill",
            text: "On your phone:\n\n1. Open Settings › About phone and tap Build number 7 times, until it says you're a developer.\n2. Go to Settings › System › Developer options.\n3. Turn on Wireless debugging and tap Allow.\n\nThe phone and the Mac must be on the same Wi-Fi for this first pairing (or plug in via USB with USB debugging enabled)."
        ),
        StepInfo(
            title: "Pair With a QR Code",
            icon: "qrcode",
            text: "1. Click Show QR Code below. A pairing code opens on the Mac.\n2. On the phone, in Wireless debugging, tap Pair device with QR code.\n3. Point the phone at the code on the Mac.\n\nDroidLink remembers the phone and reconnects automatically next time. You can also add phones later from the menu bar › Add Phone with QR Code.",
            button: "Show QR Code"
        ),
        StepInfo(
            title: "Enable Notification Access",
            icon: "iphone.gen3",
            text: "Open the DroidLink app on your phone and grant Notification Access when prompted.\n\nThis lets DroidLink forward incoming notifications to your Mac and send your quick replies back.\n\nWhen it says Connected, notifications start appearing automatically."
        ),
        StepInfo(
            title: "You're All Set",
            icon: "checkmark.seal.fill",
            text: "Your phone notifications will now appear in macOS Notification Center and in the DroidLink window.\n\n• Click Reply on any message notification to respond directly\n• Click Settings (gear icon) to choose which apps can notify on your Mac\n\nYou can reopen this guide any time from the ? button in the toolbar."
        )
    ]

    public override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 480))
        self.view = container

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

        iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Step Icon")
        iconView.contentTintColor = .droidAccent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(iconView)

        titleLabel = NSTextField(labelWithString: "Welcome to DroidLink")
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(titleLabel)

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

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sep)

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
        nextButton.title = currentStep == totalSteps - 1 ? "Get Started" : "Continue"
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
            view.window?.close()
        }
    }
}
