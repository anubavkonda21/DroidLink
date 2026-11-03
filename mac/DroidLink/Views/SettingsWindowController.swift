//
//  SettingsWindowController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

/// Window controller hosting the multi-tab settings interface.
public final class SettingsWindowController: NSWindowController {
    public static let shared = SettingsWindowController()

    public init() {
        let tabViewController = SettingsTabViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
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

        let generalVC = GeneralSettingsViewController()
        let mirrorVC = MirrorSettingsViewController()
        let clipboardVC = ClipboardSettingsViewController()
        let notificationVC = NotificationSettingsViewController()
        let fileVC = FileSettingsViewController()
        let aboutVC = AboutSettingsViewController()

        addTabViewItem(NSTabViewItem(viewController: generalVC))
        addTabViewItem(NSTabViewItem(viewController: mirrorVC))
        addTabViewItem(NSTabViewItem(viewController: clipboardVC))
        addTabViewItem(NSTabViewItem(viewController: notificationVC))
        addTabViewItem(NSTabViewItem(viewController: fileVC))
        addTabViewItem(NSTabViewItem(viewController: aboutVC))

        tabViewItems[0].label = "General"
        tabViewItems[0].image = NSImage(systemSymbolName: "gear", accessibilityDescription: "General")

        tabViewItems[1].label = "Mirroring"
        tabViewItems[1].image = NSImage(systemSymbolName: "display", accessibilityDescription: "Mirroring")

        tabViewItems[2].label = "Clipboard"
        tabViewItems[2].image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard")

        tabViewItems[3].label = "Notifications"
        tabViewItems[3].image = NSImage(systemSymbolName: "bell", accessibilityDescription: "Notifications")

        tabViewItems[4].label = "Files"
        tabViewItems[4].image = NSImage(systemSymbolName: "folder", accessibilityDescription: "Files")

        tabViewItems[5].label = "About"
        tabViewItems[5].image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")
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
        autoConnectButton.state = UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.autoConnect) ? .on : .off
        stack.addArrangedSubview(autoConnectButton)

        launchAtLoginButton = NSButton(
            checkboxWithTitle: "Launch DroidLink at system startup",
            target: self,
            action: #selector(launchAtLoginToggled(_:))
        )
        launchAtLoginButton.state = UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.launchAtLogin) ? .on : .off
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
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.launchAtLogin)
    }

    @objc private func connectionChanged(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem {
            UserDefaults.standard.set(title, forKey: MirrorSettings.StorageKeys.preferredConnection)
        }
    }
}

// MARK: - Mirroring Settings Tab

public final class MirrorSettingsViewController: NSViewController {
    private var resolutionPopUp: NSPopUpButton!
    private var fpsSegment: NSSegmentedControl!
    private var codecPopUp: NSPopUpButton!
    private var bitrateSlider: NSSlider!
    private var bitrateLabel: NSTextField!
    private var audioCheckBox: NSButton!
    private var screenOffCheckBox: NSButton!

    public override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 350))
        self.view = view

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ])

        // Resolution
        let resRow = NSStackView()
        resRow.orientation = .horizontal
        resRow.spacing = 12
        resRow.addArrangedSubview(NSTextField(labelWithString: "Max Resolution:"))
        resolutionPopUp = NSPopUpButton()
        resolutionPopUp.addItems(withTitles: ResolutionOption.allCases.map { $0.rawValue })
        let savedRes = UserDefaults.standard.string(forKey: MirrorSettings.StorageKeys.maxResolution) ?? ResolutionOption.native.rawValue
        resolutionPopUp.selectItem(withTitle: savedRes)
        resolutionPopUp.target = self
        resolutionPopUp.action = #selector(resolutionChanged(_:))
        resRow.addArrangedSubview(resolutionPopUp)
        stack.addArrangedSubview(resRow)

        // FPS
        let fpsRow = NSStackView()
        fpsRow.orientation = .horizontal
        fpsRow.spacing = 12
        fpsRow.addArrangedSubview(NSTextField(labelWithString: "Framerate Cap:"))
        fpsSegment = NSSegmentedControl(labels: ["30 FPS", "60 FPS"], trackingMode: .selectOne, target: self, action: #selector(fpsChanged(_:)))
        let savedFps = UserDefaults.standard.double(forKey: MirrorSettings.StorageKeys.maxFps)
        fpsSegment.selectedSegment = savedFps == 30.0 ? 0 : 1
        fpsRow.addArrangedSubview(fpsSegment)
        stack.addArrangedSubview(fpsRow)

        // Codec
        let codecRow = NSStackView()
        codecRow.orientation = .horizontal
        codecRow.spacing = 12
        codecRow.addArrangedSubview(NSTextField(labelWithString: "Video Codec:"))
        codecPopUp = NSPopUpButton()
        codecPopUp.addItems(withTitles: VideoCodec.allCases.map { $0.rawValue })
        let savedCodec = UserDefaults.standard.string(forKey: MirrorSettings.StorageKeys.codec) ?? VideoCodec.h264.rawValue
        codecPopUp.selectItem(withTitle: savedCodec)
        codecPopUp.target = self
        codecPopUp.action = #selector(codecChanged(_:))
        codecRow.addArrangedSubview(codecPopUp)
        stack.addArrangedSubview(codecRow)

        // Bitrate
        let savedBitrate = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.bitrateMbps) != nil ?
            UserDefaults.standard.double(forKey: MirrorSettings.StorageKeys.bitrateMbps) : 12.0
        let bitRow = NSStackView()
        bitRow.orientation = .horizontal
        bitRow.spacing = 12
        bitRow.addArrangedSubview(NSTextField(labelWithString: "Bitrate:"))
        bitrateSlider = NSSlider(value: savedBitrate, minValue: 4.0, maxValue: 30.0, target: self, action: #selector(bitrateSliderChanged(_:)))
        bitrateSlider.isContinuous = true
        bitrateSlider.widthAnchor.constraint(equalToConstant: 160).isActive = true
        bitRow.addArrangedSubview(bitrateSlider)
        bitrateLabel = NSTextField(labelWithString: String(format: "%.0f Mbps", savedBitrate))
        bitRow.addArrangedSubview(bitrateLabel)
        stack.addArrangedSubview(bitRow)

        // Audio
        let savedAudio = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.audioEnabled) != nil ?
            UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.audioEnabled) : true
        audioCheckBox = NSButton(checkboxWithTitle: "Stream Android audio to Mac speakers", target: self, action: #selector(audioToggled(_:)))
        audioCheckBox.state = savedAudio ? .on : .off
        stack.addArrangedSubview(audioCheckBox)

        // Screen Off
        let savedScreenOff = UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.turnScreenOff)
        screenOffCheckBox = NSButton(checkboxWithTitle: "Turn off device screen while mirroring", target: self, action: #selector(screenOffToggled(_:)))
        screenOffCheckBox.state = savedScreenOff ? .on : .off
        stack.addArrangedSubview(screenOffCheckBox)
    }

    @objc private func resolutionChanged(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem {
            UserDefaults.standard.set(title, forKey: MirrorSettings.StorageKeys.maxResolution)
        }
    }

    @objc private func fpsChanged(_ sender: NSSegmentedControl) {
        let fps: Double = sender.selectedSegment == 0 ? 30.0 : 60.0
        UserDefaults.standard.set(fps, forKey: MirrorSettings.StorageKeys.maxFps)
    }

    @objc private func codecChanged(_ sender: NSPopUpButton) {
        if let title = sender.titleOfSelectedItem {
            UserDefaults.standard.set(title, forKey: MirrorSettings.StorageKeys.codec)
        }
    }

    @objc private func bitrateSliderChanged(_ sender: NSSlider) {
        bitrateLabel.stringValue = String(format: "%.0f Mbps", sender.doubleValue)
        UserDefaults.standard.set(sender.doubleValue, forKey: MirrorSettings.StorageKeys.bitrateMbps)
    }

    @objc private func audioToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.audioEnabled)
    }

    @objc private func screenOffToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.turnScreenOff)
    }
}

// MARK: - Clipboard Settings Tab

public final class ClipboardSettingsViewController: NSViewController {
    private var syncCheckBox: NSButton!
    private var otpCheckBox: NSButton!

    public override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
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

        let savedSync = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.autoSyncClipboard) != nil ?
            UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.autoSyncClipboard) : true
        syncCheckBox = NSButton(checkboxWithTitle: "Automatically synchronize clipboard with Android", target: self, action: #selector(syncToggled(_:)))
        syncCheckBox.state = savedSync ? .on : .off
        stack.addArrangedSubview(syncCheckBox)

        let savedOtp = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.otpAutoForward) != nil ?
            UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.otpAutoForward) : true
        otpCheckBox = NSButton(checkboxWithTitle: "Automatically detect and forward SMS verification codes (OTP)", target: self, action: #selector(otpToggled(_:)))
        otpCheckBox.state = savedOtp ? .on : .off
        stack.addArrangedSubview(otpCheckBox)
    }

    @objc private func syncToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.autoSyncClipboard)
    }

    @objc private func otpToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.otpAutoForward)
    }
}

// MARK: - Notification Settings Tab

public final class NotificationSettingsViewController: NSViewController {
    private var notifCheckBox: NSButton!
    private var soundCheckBox: NSButton!
    private var dndCheckBox: NSButton!

    public override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
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

        let savedNotif = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.enableNotifications) != nil ?
            UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.enableNotifications) : true
        notifCheckBox = NSButton(checkboxWithTitle: "Bridge Android notifications to macOS Notification Center", target: self, action: #selector(notifToggled(_:)))
        notifCheckBox.state = savedNotif ? .on : .off
        stack.addArrangedSubview(notifCheckBox)

        let savedSound = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.notificationSound) != nil ?
            UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.notificationSound) : true
        soundCheckBox = NSButton(checkboxWithTitle: "Play sound for incoming notifications", target: self, action: #selector(soundToggled(_:)))
        soundCheckBox.state = savedSound ? .on : .off
        stack.addArrangedSubview(soundCheckBox)

        let savedDnd = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.syncDnd) != nil ?
            UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.syncDnd) : true
        dndCheckBox = NSButton(checkboxWithTitle: "Sync Do Not Disturb / Focus mode", target: self, action: #selector(dndToggled(_:)))
        dndCheckBox.state = savedDnd ? .on : .off
        stack.addArrangedSubview(dndCheckBox)
    }

    @objc private func notifToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.enableNotifications)
    }

    @objc private func soundToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.notificationSound)
    }

    @objc private func dndToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.syncDnd)
    }
}

// MARK: - File Settings Tab

public final class FileSettingsViewController: NSViewController {
    private var pathField: NSTextField!
    private var organizeCheckBox: NSButton!

    public override func loadView() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
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

        let pathLabel = NSTextField(labelWithString: "Default Download Directory:")
        stack.addArrangedSubview(pathLabel)

        let pathRow = NSStackView()
        pathRow.orientation = .horizontal
        pathRow.spacing = 8

        let defaultPath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/Users/Shared"
        let savedPath = UserDefaults.standard.string(forKey: MirrorSettings.StorageKeys.downloadDirectory) ?? defaultPath

        pathField = NSTextField(string: savedPath.isEmpty ? defaultPath : savedPath)
        pathField.isEditable = false
        pathField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        pathRow.addArrangedSubview(pathField)

        let browseBtn = NSButton(title: "Choose...", target: self, action: #selector(browseClicked(_:)))
        pathRow.addArrangedSubview(browseBtn)
        stack.addArrangedSubview(pathRow)

        let savedOrg = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.autoOrganizeFiles) != nil ?
            UserDefaults.standard.bool(forKey: MirrorSettings.StorageKeys.autoOrganizeFiles) : true
        organizeCheckBox = NSButton(checkboxWithTitle: "Automatically organize received files by type", target: self, action: #selector(organizeToggled(_:)))
        organizeCheckBox.state = savedOrg ? .on : .off
        stack.addArrangedSubview(organizeCheckBox)
    }

    @objc private func browseClicked(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            pathField.stringValue = url.path
            UserDefaults.standard.set(url.path, forKey: MirrorSettings.StorageKeys.downloadDirectory)
        }
    }

    @objc private func organizeToggled(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: MirrorSettings.StorageKeys.autoOrganizeFiles)
    }
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
        iconImageView.image = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "DroidLink")
        iconImageView.contentTintColor = .droidAccent
        iconImageView.widthAnchor.constraint(equalToConstant: 64).isActive = true
        iconImageView.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(iconImageView)

        let titleLabel = NSTextField(labelWithString: "DroidLink")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(titleLabel)

        let verLabel = NSTextField(labelWithString: "Version 1.0.0 (Pure AppKit)")
        verLabel.font = .systemFont(ofSize: 12)
        verLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(verLabel)

        let descLabel = NSTextField(labelWithString: "High-performance screen mirroring & companion suite for Android & macOS.")
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
