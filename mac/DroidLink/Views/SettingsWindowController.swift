//
//  SettingsWindowController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit
import ServiceManagement

/// Window controller hosting notification and connection preferences.
public final class SettingsWindowController: NSWindowController {
    public static let shared = SettingsWindowController()

    public init() {
        let tabViewController = SettingsTabViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DroidLink Settings"
        window.contentViewController = tabViewController
        window.center()
        super.init(window: window)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func showSettings() {
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Tab container view controller for preferences.
public final class SettingsTabViewController: NSTabViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar

        let notificationVC = NotificationSettingsViewController()
        let generalVC = GeneralSettingsViewController()
        let aboutVC = AboutSettingsViewController()

        addTabViewItem(NSTabViewItem(viewController: notificationVC))
        addTabViewItem(NSTabViewItem(viewController: generalVC))
        addTabViewItem(NSTabViewItem(viewController: aboutVC))

        tabViewItems[0].label = "Notifications"
        tabViewItems[0].image = NSImage(systemSymbolName: "bell", accessibilityDescription: "Notifications")

        tabViewItems[1].label = "General"
        tabViewItems[1].image = NSImage(systemSymbolName: "gear", accessibilityDescription: "General")

        tabViewItems[2].label = "About"
        tabViewItems[2].image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
    }
}

// MARK: - General Settings Tab

public final class GeneralSettingsViewController: NSViewController {
    private var autoConnectButton: NSButton!
    private var launchAtLoginButton: NSButton!
    private var connectionPopUp: NSPopUpButton!

    public override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 320))
        self.view = view

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        autoConnectButton = NSButton(
            checkboxWithTitle: "Automatically connect to trusted devices",
            target: self,
            action: #selector(autoConnectToggled(_:))
        )
        let savedAuto = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.autoConnect) as? Bool ?? true
        autoConnectButton.state = savedAuto ? .on : .off
        stack.addArrangedSubview(autoConnectButton)

        launchAtLoginButton = NSButton(
            checkboxWithTitle: "Launch DroidLink in background at login",
            target: self,
            action: #selector(launchAtLoginToggled(_:))
        )
        let isRegistered = SMAppService.mainApp.status == .enabled
        launchAtLoginButton.state = isRegistered ? .on : .off
        stack.addArrangedSubview(launchAtLoginButton)

        let connRow = NSStackView()
        connRow.orientation = .horizontal
        connRow.spacing = 12

        let connLabel = NSTextField(labelWithString: "Preferred Connection:")
        connRow.addArrangedSubview(connLabel)

        connectionPopUp = NSPopUpButton()
        connectionPopUp.addItems(withTitles: ["USB", "Wi-Fi (mDNS)"])
        let savedConn = UserDefaults.standard.string(forKey: MirrorSettings.StorageKeys.preferredConnection) ?? "USB"
        connectionPopUp.selectItem(withTitle: savedConn)
        connectionPopUp.target = self
        connectionPopUp.action = #selector(connectionChanged(_:))
        connRow.addArrangedSubview(connectionPopUp)

        stack.addArrangedSubview(connRow)
    }

    @objc private func autoConnectToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.autoConnect)
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        let enable = sender.state == .on
        UserDefaults.standard.set(enable, forKey: MirrorSettings.StorageKeys.launchAtLogin)
        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Launch at login update failed: \(error)")
        }
    }

    @objc private func connectionChanged(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem {
            UserDefaults.standard.set(title, forKey: MirrorSettings.StorageKeys.preferredConnection)
        }
    }
}

// MARK: - Notification Settings Tab

public final class NotificationSettingsViewController: NSViewController {
    private var notifCheckBox: NSSwitch!
    private var soundCheckBox: NSSwitch!
    private let appListStack = NSStackView()
    private var bridge: NotificationBridge { .shared }

    public override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 430))
        self.view = view
        preferredContentSize = view.frame.size

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])

        let savedNotif = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.enableNotifications) != nil ?
            UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.enableNotifications) : true
        notifCheckBox = NSSwitch()
        notifCheckBox.target = self
        notifCheckBox.action = #selector(notifToggled(_:))
        notifCheckBox.state = savedNotif ? .on : .off
        stack.addArrangedSubview(switchRow("Bridge Android notifications to macOS Notification Center", notifCheckBox))

        let savedSound = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.notificationSound) != nil ?
            UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.notificationSound) : true
        soundCheckBox = NSSwitch()
        soundCheckBox.target = self
        soundCheckBox.action = #selector(soundToggled(_:))
        soundCheckBox.state = savedSound ? .on : .off
        stack.addArrangedSubview(switchRow("Play sound for incoming notifications", soundCheckBox))

        // Per-app on/off list
        let headerRow = NSStackView()
        headerRow.orientation = .horizontal
        headerRow.spacing = 8
        let header = NSTextField(labelWithString: "Show notifications from these apps:")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        headerRow.addArrangedSubview(header)
        headerRow.addArrangedSubview(NSView())
        let allOn = NSButton(title: "All On", target: self, action: #selector(allOnClicked(_:)))
        allOn.controlSize = .small
        let allOff = NSButton(title: "All Off", target: self, action: #selector(allOffClicked(_:)))
        allOff.controlSize = .small
        headerRow.addArrangedSubview(allOn)
        headerRow.addArrangedSubview(allOff)
        stack.addArrangedSubview(headerRow)
        headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        appListStack.orientation = .vertical
        appListStack.alignment = .leading
        appListStack.spacing = 8
        appListStack.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        appListStack.translatesAutoresizingMaskIntoConstraints = false

        let clip = FlippedClipView()
        clip.drawsBackground = false
        let scroll = NSScrollView()
        scroll.contentView = clip
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        scroll.documentView = appListStack
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 220),
            appListStack.topAnchor.constraint(equalTo: clip.topAnchor),
            appListStack.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            appListStack.widthAnchor.constraint(equalTo: clip.widthAnchor)
        ])

        let hint = NSTextField(labelWithString: "Apps are added here the first time they send a notification. Turned-off apps stay silent on the Mac but still notify on your phone.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.maximumNumberOfLines = 0
        hint.preferredMaxLayoutWidth = 436
        stack.addArrangedSubview(hint)

        rebuildAppList()
        NotificationCenter.default.addObserver(self, selector: #selector(appFilterChanged(_:)),
                                               name: NotificationBridge.didUpdateAppFilterNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func rebuildAppList() {
        appListStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let apps = bridge.knownApps.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
        if apps.isEmpty {
            let empty = NSTextField(labelWithString: "No apps yet. Connect your phone and they'll show up as notifications arrive.")
            empty.textColor = .secondaryLabelColor
            empty.lineBreakMode = .byWordWrapping
            empty.maximumNumberOfLines = 0
            empty.preferredMaxLayoutWidth = 400
            appListStack.addArrangedSubview(empty)
            return
        }
        for (pkg, name) in apps {
            let box = NSButton(checkboxWithTitle: name, target: self, action: #selector(appToggled(_:)))
            box.identifier = NSUserInterfaceItemIdentifier(pkg)
            box.toolTip = pkg
            box.state = bridge.isAppEnabled(pkg) ? .on : .off
            appListStack.addArrangedSubview(box)
        }
    }

    @objc private func appFilterChanged(_ note: Notification) {
        DispatchQueue.main.async { [weak self] in self?.rebuildAppList() }
    }

    @objc private func appToggled(_ sender: NSButton) {
        guard let pkg = sender.identifier?.rawValue else { return }
        bridge.setApp(pkg, enabled: sender.state == .on)
    }

    @objc private func allOnClicked(_ sender: NSButton) { bridge.setAllApps(enabled: true) }
    @objc private func allOffClicked(_ sender: NSButton) { bridge.setAllApps(enabled: false) }

    @objc private func notifToggled(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.enableNotifications)
    }

    @objc private func soundToggled(_ sender: NSSwitch) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.notificationSound)
    }
}

/// Keeps the app list pinned to the top of its scroll view.
private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - About Settings Tab

public final class AboutSettingsViewController: NSViewController {
    public override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 320))
        self.view = view

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 40),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32)
        ])

        let iconImageView = NSImageView()
        iconImageView.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "DroidLink")
        iconImageView.contentTintColor = .droidAccent
        iconImageView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(iconImageView)

        let titleLabel = NSTextField(labelWithString: "DroidLink")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(titleLabel)

        let verLabel = NSTextField(labelWithString: "Version 1.0.0 (Notifications Edition)")
        verLabel.font = .systemFont(ofSize: 12)
        verLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(verLabel)

        let descLabel = NSTextField(labelWithString: "Android phone notifications bridged directly to your Mac.")
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.alignment = .center
        stack.addArrangedSubview(descLabel)

        let copyrightLabel = NSTextField(labelWithString: "Copyright © 2026 DroidLink Team. All rights reserved.")
        copyrightLabel.font = .systemFont(ofSize: 11)
        copyrightLabel.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(copyrightLabel)
    }
}

/// Apple-style settings row: label on the left, a native switch on the right.
private func switchRow(_ title: String, _ toggle: NSSwitch) -> NSView {
    let label = NSTextField(labelWithString: title)
    label.lineBreakMode = .byWordWrapping
    label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let row = NSStackView(views: [label, NSView(), toggle])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    row.widthAnchor.constraint(equalToConstant: 440).isActive = true
    return row
}
