//
//  MainSplitViewController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

/// Root view controller presenting phone notifications and the connection toolbar.
public final class MainSplitViewController: NSViewController, NSToolbarDelegate {
    private var connectionManager: ConnectionManager { ConnectionManager.shared }
    private let notificationVC = NotificationViewController()

    // Toolbar components
    private var statusDotView: NSView!
    private var statusDeviceLabel: NSTextField!
    private var connectButton: NSButton!

    public override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 620))
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        addChild(notificationVC)
        let childView = notificationVC.view
        childView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(childView)

        NSLayoutConstraint.activate([
            childView.topAnchor.constraint(equalTo: view.topAnchor),
            childView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        setupNotifications()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        setupWindowToolbar()
        updateToolbarState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Toolbar Setup

    private func setupWindowToolbar() {
        guard let window = view.window, window.toolbar == nil else { return }

        let toolbar = NSToolbar(identifier: "MainAppToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            NSToolbarItem.Identifier("HelpItem"),
            NSToolbarItem.Identifier("SettingsItem"),
            NSToolbarItem.Identifier("StatusItem"),
            NSToolbarItem.Identifier("ConnectItem")
        ]
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .flexibleSpace,
            NSToolbarItem.Identifier("HelpItem"),
            NSToolbarItem.Identifier("SettingsItem"),
            NSToolbarItem.Identifier("StatusItem"),
            NSToolbarItem.Identifier("ConnectItem")
        ]
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier.rawValue {
        case "StatusItem":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)

            let pillView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
            pillView.wantsLayer = true
            pillView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            pillView.layer?.cornerRadius = 14

            statusDotView = NSView()
            statusDotView.wantsLayer = true
            statusDotView.layer?.cornerRadius = 4
            statusDotView.layer?.backgroundColor = NSColor.systemRed.cgColor
            statusDotView.translatesAutoresizingMaskIntoConstraints = false
            pillView.addSubview(statusDotView)

            statusDeviceLabel = NSTextField(labelWithString: "Disconnected")
            statusDeviceLabel.font = .systemFont(ofSize: 12, weight: .semibold)
            statusDeviceLabel.lineBreakMode = .byTruncatingTail
            statusDeviceLabel.translatesAutoresizingMaskIntoConstraints = false
            pillView.addSubview(statusDeviceLabel)

            NSLayoutConstraint.activate([
                statusDotView.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 10),
                statusDotView.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
                statusDotView.widthAnchor.constraint(equalToConstant: 8),
                statusDotView.heightAnchor.constraint(equalToConstant: 8),

                statusDeviceLabel.leadingAnchor.constraint(equalTo: statusDotView.trailingAnchor, constant: 8),
                statusDeviceLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
                statusDeviceLabel.trailingAnchor.constraint(lessThanOrEqualTo: pillView.trailingAnchor, constant: -10)
            ])

            item.view = pillView
            return item

        case "ConnectItem":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            connectButton = NSButton(title: "Connect", target: self, action: #selector(toggleConnection(_:)))
            connectButton.bezelStyle = .rounded
            item.view = connectButton
            return item

        case "SettingsItem":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Settings"
            item.toolTip = "Notification Settings"
            let btn = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")!,
                               target: self, action: #selector(openSettings(_:)))
            btn.bezelStyle = .texturedRounded
            item.view = btn
            return item

        case "HelpItem":
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Setup Guide"
            item.toolTip = "Setup Guide"
            let btn = NSButton(image: NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Setup Guide")!,
                               target: self, action: #selector(openWizard(_:)))
            btn.bezelStyle = .texturedRounded
            item.view = btn
            return item

        default:
            return nil
        }
    }

    private func updateToolbarState() {
        let isConnected = connectionManager.status.isConnected

        if let dot = statusDotView {
            dot.layer?.backgroundColor = isConnected ? NSColor.systemGreen.cgColor : NSColor.systemRed.cgColor
        }

        if let label = statusDeviceLabel {
            if let info = connectionManager.currentDeviceInfo, isConnected {
                label.stringValue = info.name
            } else {
                label.stringValue = connectionManager.status.statusTitle
            }
        }

        if let btn = connectButton {
            btn.title = isConnected ? "Disconnect" : "Connect"
        }
    }

    @objc private func toggleConnection(_ sender: NSButton) {
        if connectionManager.status.isConnected {
            connectionManager.disconnect()
        } else {
            if let first = connectionManager.deviceDiscovery.discoveredDevices.first {
                connectionManager.connect(to: first)
            } else if let adbDev = connectionManager.adbService.devices.first(where: { $0.state == .device }) {
                let disc = DiscoveredDevice(
                    id: adbDev.serial,
                    name: adbDev.model ?? "Android Device",
                    model: adbDev.model ?? "Android",
                    transport: adbDev.isWireless ? .wirelessAdb : .usb,
                    adbSerial: adbDev.serial,
                    isPaired: true
                )
                connectionManager.connect(to: disc)
            } else {
                let alert = NSAlert()
                alert.messageText = "No Devices Found"
                alert.informativeText = "Connect your Android phone via USB with USB Debugging enabled, or pair via QR code from the menu bar."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    @objc private func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func openWizard(_ sender: Any?) {
        OnboardingWindowController.shared.showWizard()
    }

    // MARK: - Notifications

    private func setupNotifications() {
        let names: [Notification.Name] = [
            ConnectionManager.didChangeStatusNotification,
            ConnectionManager.didChangeDeviceInfoNotification,
            DeviceDiscovery.didUpdateDevicesNotification,
            ADBService.didUpdateDevicesNotification
        ]
        for name in names {
            NotificationCenter.default.addObserver(self, selector: #selector(stateChanged(_:)), name: name, object: nil)
        }
    }

    @objc private func stateChanged(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateToolbarState()
        }
    }
}
