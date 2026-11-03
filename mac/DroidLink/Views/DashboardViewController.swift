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
    private weak var webcamButton: NSButton?

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
        scrollView.autoresizingMask = [.width, .height]

        // Frosted window background: the desktop shows through, blurred, like Apple's own apps
        let glass = NSVisualEffectView(frame: scrollView.frame)
        glass.material = .underWindowBackground
        glass.blendingMode = .behindWindow
        glass.state = .followsWindowActiveState
        glass.addSubview(scrollView)
        self.view = glass

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

        // 2x2 grid: rows span the full width, both cards in a row share width and height
        for (left, right) in [(createBatteryCard(), createStorageCard()), (createDisplayCard(), createNetworkCard())] {
            let row = NSStackView(views: [left, right])
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.alignment = .top
            row.spacing = 16
            metricsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: metricsStack.widthAnchor).isActive = true
            right.heightAnchor.constraint(equalTo: left.heightAnchor).isActive = true
        }

        // Notification registration
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshWebcamTile),
            name: AppDelegate.webcamStateChanged,
            object: nil
        )
        refreshWebcamTile()
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

    /// Glass card: a lighter frosted panel with a hairline highlight border.
    private func createCardView() -> NSView {
        let card = NSVisualEffectView()
        card.material = .popover
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
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

        let refreshBtn = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")!, target: self, action: #selector(refreshClicked(_:)))
        refreshBtn.bezelStyle = .rounded
        refreshBtn.toolTip = "Refresh phone info"
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
        btnRow.distribution = .fillEqually
        btnRow.spacing = 12

        // (title, SF symbol, tooltip, action): equal-width tiles, icon above text
        let actions: [(String, String, String, Selector)] = [
            ("Mirror", "iphone.gen3", "Show and control the phone screen", #selector(mirrorClicked(_:))),
            ("Find My Phone", "speaker.wave.3.fill", "Ring the phone loudly for 15 seconds", #selector(findPhoneClicked(_:))),
            ("Do Not Disturb", "moon.fill", "Choose the phone's Do Not Disturb mode", #selector(dndClicked(_:))),
            ("Send File", "square.and.arrow.up", "Send files from this Mac to the phone", #selector(sendFileClicked(_:))),
            ("Webcam", "video.fill", "Use the phone camera as \"OBS Virtual Camera\" in calls; click again to stop", #selector(webcamClicked(_:)))
        ]
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        for (title, symbol, tip, action) in actions {
            let button = GlassTileButton(title: title, target: self, action: action)
            button.isBordered = false // the convenience init re-enables the default bezel
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?.withSymbolConfiguration(symbolConfig)
            button.imagePosition = .imageAbove
            button.imageHugsTitle = true // centre icon + label together instead of pinning the icon to the top
            button.setContentHuggingPriority(.defaultLow, for: .horizontal)
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            button.contentTintColor = .controlAccentColor
            button.toolTip = tip
            button.heightAnchor.constraint(equalToConstant: 64).isActive = true
            btnRow.addArrangedSubview(button)
            if action == #selector(webcamClicked(_:)) { webcamButton = button }
            if let first = btnRow.arrangedSubviews.first, first !== button {
                button.widthAnchor.constraint(equalTo: first.widthAnchor).isActive = true
            }
        }

        stack.addArrangedSubview(btnRow)
        btnRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
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
        titleRow.addArrangedSubview(NSTextField(labelWithString: "Battery"))
        stack.addArrangedSubview(titleRow)

        batteryPercentLabel = NSTextField(labelWithString: "—")
        batteryPercentLabel.font = .systemFont(ofSize: 24, weight: .bold)
        stack.addArrangedSubview(batteryPercentLabel)

        batteryProgress = NSProgressIndicator()
        batteryProgress.isIndeterminate = false
        batteryProgress.minValue = 0
        batteryProgress.maxValue = 100
                batteryProgress.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(batteryProgress)
        batteryProgress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        batteryStatusLabel = NSTextField(labelWithString: "—")
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
        titleRow.addArrangedSubview(NSTextField(labelWithString: "Storage"))
        stack.addArrangedSubview(titleRow)

        storagePercentLabel = NSTextField(labelWithString: "—")
        storagePercentLabel.font = .systemFont(ofSize: 24, weight: .bold)
        stack.addArrangedSubview(storagePercentLabel)

        storageProgress = NSProgressIndicator()
        storageProgress.isIndeterminate = false
        storageProgress.minValue = 0
        storageProgress.maxValue = 100
                storageProgress.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(storageProgress)
        storageProgress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        storageDetailsLabel = NSTextField(labelWithString: "—")
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
        titleRow.addArrangedSubview(NSTextField(labelWithString: "Screen"))
        stack.addArrangedSubview(titleRow)

        screenResolutionLabel = NSTextField(labelWithString: "—")
        screenResolutionLabel.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(screenResolutionLabel)

        screenDpiLabel = NSTextField(labelWithString: "—")
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
        titleRow.addArrangedSubview(NSTextField(labelWithString: "Connection"))
        stack.addArrangedSubview(titleRow)

        latencyLabel = NSTextField(labelWithString: "—")
        latencyLabel.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(latencyLabel)

        networkTypeLabel = NSTextField(labelWithString: "—")
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

            latencyLabel.stringValue = "—"
            batteryPercentLabel.textColor = .labelColor
            networkTypeLabel.stringValue = "Not Connected"
            return
        }

        deviceNameLabel.stringValue = device.name
        deviceSubLabel.stringValue = "\(device.model) • \(device.androidVersion)"
        connectionTypeLabel.stringValue = device.connectionType.rawValue

        batteryPercentLabel.stringValue = "\(device.batteryLevel)%"
        batteryProgress.doubleValue = Double(device.batteryLevel)
        batteryStatusLabel.stringValue = device.isCharging ? "Charging" : "On battery"
        // NSProgressIndicator ignores tint, so color the percentage instead
        batteryPercentLabel.textColor = device.isCharging || device.batteryLevel > 30 ? .systemGreen
            : device.batteryLevel >= 15 ? .systemOrange : .systemRed

        let totalGB = max(1, device.storageTotal / 1_000_000_000)
        let freeGB = device.storageFree / 1_000_000_000
        let usedGB = totalGB - freeGB
        let storageRatio = Double(usedGB) / Double(totalGB) * 100.0
        storagePercentLabel.stringValue = "\(freeGB) GB Free"
        storageProgress.doubleValue = storageRatio
        storageDetailsLabel.stringValue = "\(usedGB) GB used of \(totalGB) GB"

        screenResolutionLabel.stringValue = "\(device.screenWidth) × \(device.screenHeight)"
        screenDpiLabel.stringValue = "\(device.screenDpi) dpi"

        latencyLabel.stringValue = device.connectionType == .usb ? "USB" : "Wi-Fi"
        networkTypeLabel.stringValue = [device.ipAddress, connectionManager.latencyMs > 0 ? "\(connectionManager.latencyMs) ms" : nil]
            .compactMap { $0 }.joined(separator: " • ")
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

    @objc private func mirrorClicked(_ sender: NSButton) {
        (parent as? MainSplitViewController)?.launchScrcpyMirror()
    }

    @objc private func sendFileClicked(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            connectionManager.fileTransferService.sendFiles(urls: panel.urls)
        }
    }

    @objc private func webcamClicked(_ sender: NSButton) {
        (NSApp.delegate as? AppDelegate)?.toggleWebcam(sender)
    }

    /// While the webcam runs the tile turns into a red "Stop Webcam" button.
    @objc private func refreshWebcamTile() {
        guard let button = webcamButton else { return }
        let on = (NSApp.delegate as? AppDelegate)?.isWebcamOn == true
        button.title = on ? "Stop Webcam" : "Webcam"
        button.image = NSImage(systemSymbolName: on ? "stop.circle.fill" : "video.fill", accessibilityDescription: button.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 20, weight: .regular))
        button.contentTintColor = on ? .systemRed : .controlAccentColor
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

/// Borderless translucent tile that brightens on hover and dims while pressed.
final class GlassTileButton: NSButton {
    private var hovering = false { didSet { updateFill() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor
        updateFill()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override var isHighlighted: Bool { didSet { updateFill() } }

    private func updateFill() {
        let alpha: CGFloat = isHighlighted ? 0.04 : hovering ? 0.16 : 0.08
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
        }
    }
}
