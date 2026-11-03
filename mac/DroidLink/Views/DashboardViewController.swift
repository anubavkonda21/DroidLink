//
//  DashboardViewController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

/// Dashboard view providing a comprehensive health overview of the connected Android device,
/// including battery telemetry, storage utilization, network status, and quick ecosystem actions.
public final class DashboardViewController: NSViewController {
    private var connectionManager: ConnectionManager { ConnectionManager.shared }

    private var deviceNameLabel: NSTextField!
    private var deviceSubLabel: NSTextField!
    private var connectionTypeLabel: NSTextField!

    private var batteryPercentLabel: NSTextField!
    private var batteryStatusLabel: NSTextField!
    private var batteryProgress: NSProgressIndicator!

    private var storagePercentLabel: NSTextField!
    private var storageDetailsLabel: NSTextField!
    private var storageProgress: NSProgressIndicator!

    private var screenResolutionLabel: NSTextField!
    private var screenDpiLabel: NSTextField!

    private var networkTypeLabel: NSTextField!
    private var networkIpLabel: NSTextField!
    private var latencyLabel: NSTextField!

    public override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        self.view = scrollView

        let content = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = content

        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 24
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(mainStack)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            mainStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            mainStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            mainStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            mainStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -28)
        ])

        // 1. Header Banner
        let headerCard = createHeaderCard()
        mainStack.addArrangedSubview(headerCard)
        headerCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // 2. Quick Actions
        let quickActionsCard = createQuickActionsCard()
        mainStack.addArrangedSubview(quickActionsCard)
        quickActionsCard.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        // 3. Telemetry Cards (Grid / Stack)
        let metricsStack = NSStackView()
        metricsStack.orientation = .vertical
        metricsStack.spacing = 16
        metricsStack.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(metricsStack)
        metricsStack.widthAnchor.constraint(equalTo: mainStack.widthAnchor).isActive = true

        let row1 = NSStackView()
        row1.orientation = .horizontal
        row1.distribution = .fillEqually
        row1.spacing = 16
        row1.addArrangedSubview(createBatteryCard())
        row1.addArrangedSubview(createStorageCard())
        metricsStack.addArrangedSubview(row1)

        let row2 = NSStackView()
        row2.orientation = .horizontal
        row2.distribution = .fillEqually
        row2.spacing = 16
        row2.addArrangedSubview(createDisplayCard())
        row2.addArrangedSubview(createNetworkCard())
        metricsStack.addArrangedSubview(row2)

        // Notification registration
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDataChanged(_:)),
            name: ConnectionManager.didChangeDeviceInfoNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDataChanged(_:)),
            name: ConnectionManager.didChangeStatusNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceDataChanged(_:)),
            name: ConnectionManager.didChangeLatencyNotification,
            object: nil
        )

        updateDeviceTelemetry()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Card Builders

    private func createCardView() -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        return card
    }

    private func createHeaderCard() -> NSView {
        let card = createCardView()
        card.heightAnchor.constraint(equalToConstant: 90).isActive = true

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 18
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "smartphone", accessibilityDescription: "Device")
        iconView.contentTintColor = .systemBlue
        iconView.widthAnchor.constraint(equalToConstant: 44).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 44).isActive = true
        stack.addArrangedSubview(iconView)

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 4

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 8

        deviceNameLabel = NSTextField(labelWithString: "No Device Connected")
        deviceNameLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleRow.addArrangedSubview(deviceNameLabel)

        connectionTypeLabel = NSTextField(labelWithString: "—")
        connectionTypeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        connectionTypeLabel.textColor = .systemBlue
        titleRow.addArrangedSubview(connectionTypeLabel)
        labelStack.addArrangedSubview(titleRow)

        deviceSubLabel = NSTextField(labelWithString: "Connect your Android device to get started")
        deviceSubLabel.font = .systemFont(ofSize: 12)
        deviceSubLabel.textColor = .secondaryLabelColor
        labelStack.addArrangedSubview(deviceSubLabel)

        stack.addArrangedSubview(labelStack)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        let refreshBtn = NSButton(title: "Refresh Telemetry", target: self, action: #selector(refreshClicked(_:)))
        refreshBtn.bezelStyle = .rounded
        stack.addArrangedSubview(refreshBtn)

        return card
    }

    private func createQuickActionsCard() -> NSView {
        let card = createCardView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        let title = NSTextField(labelWithString: "Quick Actions")
        title.font = .systemFont(ofSize: 14, weight: .bold)
        stack.addArrangedSubview(title)

        let btnRow = NSStackView()
        btnRow.orientation = .horizontal
        btnRow.spacing = 12

        let findBtn = NSButton(title: "Find My Phone", target: self, action: #selector(findPhoneClicked(_:)))
        findBtn.image = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "Find Phone")
        btnRow.addArrangedSubview(findBtn)

        let dndBtn = NSButton(title: "Do Not Disturb", target: self, action: #selector(dndClicked(_:)))
        dndBtn.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Do Not Disturb")
        btnRow.addArrangedSubview(dndBtn)

        // Icon + text, with a tooltip, so each action is self-explanatory
        let tips = ["Ring the phone loudly for 15 seconds", "Choose the phone's Do Not Disturb mode"]
        for (button, tip) in zip(btnRow.arrangedSubviews.compactMap { $0 as? NSButton }, tips) {
            button.imagePosition = .imageLeading
            button.bezelStyle = .rounded
            button.toolTip = tip
        }

        stack.addArrangedSubview(btnRow)
        return card
    }

    private func createBatteryCard() -> NSView {
        let card = createCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 6
        let icon = NSImageView(image: NSImage(systemSymbolName: "battery.100.bolt", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemGreen
        titleRow.addArrangedSubview(icon)
        titleRow.addArrangedSubview(NSTextField(labelWithString: "Battery Status"))
        stack.addArrangedSubview(titleRow)

        batteryPercentLabel = NSTextField(labelWithString: "85%")
        batteryPercentLabel.font = .systemFont(ofSize: 24, weight: .bold)
        stack.addArrangedSubview(batteryPercentLabel)

        batteryProgress = NSProgressIndicator()
        batteryProgress.isIndeterminate = false
        batteryProgress.minValue = 0
        batteryProgress.maxValue = 100
        batteryProgress.doubleValue = 85
        batteryProgress.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(batteryProgress)
        batteryProgress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        batteryStatusLabel = NSTextField(labelWithString: "Charging • Fast Wireless")
        batteryStatusLabel.font = .systemFont(ofSize: 11)
        batteryStatusLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(batteryStatusLabel)

        return card
    }

    private func createStorageCard() -> NSView {
        let card = createCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 6
        let icon = NSImageView(image: NSImage(systemSymbolName: "internaldrive.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemOrange
        titleRow.addArrangedSubview(icon)
        titleRow.addArrangedSubview(NSTextField(labelWithString: "Device Storage"))
        stack.addArrangedSubview(titleRow)

        storagePercentLabel = NSTextField(labelWithString: "64 GB Free")
        storagePercentLabel.font = .systemFont(ofSize: 24, weight: .bold)
        stack.addArrangedSubview(storagePercentLabel)

        storageProgress = NSProgressIndicator()
        storageProgress.isIndeterminate = false
        storageProgress.minValue = 0
        storageProgress.maxValue = 100
        storageProgress.doubleValue = 50
        storageProgress.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(storageProgress)
        storageProgress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        storageDetailsLabel = NSTextField(labelWithString: "64 GB used of 128 GB")
        storageDetailsLabel.font = .systemFont(ofSize: 11)
        storageDetailsLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(storageDetailsLabel)

        return card
    }

    private func createDisplayCard() -> NSView {
        let card = createCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 6
        let icon = NSImageView(image: NSImage(systemSymbolName: "display", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemPurple
        titleRow.addArrangedSubview(icon)
        titleRow.addArrangedSubview(NSTextField(labelWithString: "Display Specs"))
        stack.addArrangedSubview(titleRow)

        screenResolutionLabel = NSTextField(labelWithString: "1080 × 2400")
        screenResolutionLabel.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(screenResolutionLabel)

        screenDpiLabel = NSTextField(labelWithString: "420 DPI • 60 Hz Stream Target")
        screenDpiLabel.font = .systemFont(ofSize: 11)
        screenDpiLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(screenDpiLabel)

        return card
    }

    private func createNetworkCard() -> NSView {
        let card = createCardView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        let titleRow = NSStackView()
        titleRow.orientation = .horizontal
        titleRow.spacing = 6
        let icon = NSImageView(image: NSImage(systemSymbolName: "wifi", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemTeal
        titleRow.addArrangedSubview(icon)
        titleRow.addArrangedSubview(NSTextField(labelWithString: "Network & Stream"))
        stack.addArrangedSubview(titleRow)

        latencyLabel = NSTextField(labelWithString: "\(connectionManager.latencyMs) ms Latency")
        latencyLabel.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(latencyLabel)

        networkTypeLabel = NSTextField(labelWithString: "Direct USB ADB Bridge")
        networkTypeLabel.font = .systemFont(ofSize: 11)
        networkTypeLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(networkTypeLabel)

        return card
    }

    // MARK: - Telemetry Updating

    @objc private func deviceDataChanged(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateDeviceTelemetry()
        }
    }

    private func updateDeviceTelemetry() {
        guard let device = connectionManager.currentDeviceInfo,
              connectionManager.status.isConnectedOrMirroring else {
            // No device connected — show placeholder state
            deviceNameLabel.stringValue = "No Device Connected"
            deviceSubLabel.stringValue = "Connect your Android device to get started"
            connectionTypeLabel.stringValue = "—"

            batteryPercentLabel.stringValue = "—%"
            batteryProgress.doubleValue = 0
            batteryStatusLabel.stringValue = "N/A"

            storagePercentLabel.stringValue = "—"
            storageProgress.doubleValue = 0
            storageDetailsLabel.stringValue = "—"

            screenResolutionLabel.stringValue = "—"
            screenDpiLabel.stringValue = "—"

            latencyLabel.stringValue = "— ms"
            networkTypeLabel.stringValue = "Not Connected"
            return
        }

        deviceNameLabel.stringValue = device.name
        deviceSubLabel.stringValue = "\(device.model) • \(device.androidVersion)"
        connectionTypeLabel.stringValue = device.connectionType.rawValue

        batteryPercentLabel.stringValue = "\(device.batteryLevel)%"
        batteryProgress.doubleValue = Double(device.batteryLevel)
        batteryStatusLabel.stringValue = device.isCharging ? "Charging" : "Discharging"

        let totalGB = max(1, device.storageTotal / 1_000_000_000)
        let freeGB = device.storageFree / 1_000_000_000
        let usedGB = totalGB - freeGB
        let storageRatio = Double(usedGB) / Double(totalGB) * 100.0
        storagePercentLabel.stringValue = "\(freeGB) GB Free"
        storageProgress.doubleValue = storageRatio
        storageDetailsLabel.stringValue = "\(usedGB) GB used of \(totalGB) GB"

        screenResolutionLabel.stringValue = "\(device.screenWidth) × \(device.screenHeight)"
        screenDpiLabel.stringValue = "\(device.screenDpi) DPI • 60 Hz Stream Target"

        latencyLabel.stringValue = "\(connectionManager.latencyMs) ms Latency"
        networkTypeLabel.stringValue = device.connectionType == .usb ? "Direct USB ADB Bridge" : (device.ipAddress ?? "Wi-Fi (Active)")
    }

    // MARK: - Actions

    @objc private func refreshClicked(_ sender: NSButton) {
        Task {
            if let serial = connectionManager.adbService.selectedDevice?.serial {
                if let updated = try? await connectionManager.adbService.fetchDeviceInfo(serial: serial) {
                    connectionManager.currentDeviceInfo = updated
                }
            }
        }
    }

    @objc private func findPhoneClicked(_ sender: NSButton) {
        connectionManager.sendControlMessage(type: .findPhone, payload: [String: String]())
    }

    /// (title, `cmd notification set_dnd` argument, matching `zen_mode` value)
    private let dndModes: [(String, String, String)] = [
        ("Off", "off", "0"),
        ("Priority only", "priority", "1"),
        ("Alarms only", "alarms", "3"),
        ("Total silence", "none", "2")
    ]

    /// Shows the phone's Do Not Disturb modes, with the current one ticked.
    @objc private func dndClicked(_ sender: NSButton) {
        let adb = connectionManager.adbService
        Task {
            let current = (try? await adb.executeADB(["shell", "settings", "get", "global", "zen_mode"]))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            await MainActor.run {
                let menu = NSMenu()
                for (i, mode) in self.dndModes.enumerated() {
                    let item = NSMenuItem(title: mode.0, action: #selector(self.dndModeChosen(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = i
                    item.state = mode.2 == current ? .on : .off
                    menu.addItem(item)
                }
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
            }
        }
    }

    @objc private func dndModeChosen(_ item: NSMenuItem) {
        let mode = dndModes[item.tag]
        Task {
            let ok = (try? await connectionManager.adbService.executeADB(["shell", "cmd", "notification", "set_dnd", mode.1])) != nil
            if !ok {
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Couldn't change Do Not Disturb"
                    alert.runModal()
                }
            }
        }
    }
}
