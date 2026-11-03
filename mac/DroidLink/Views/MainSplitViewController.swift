//
//  MainSplitViewController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

public enum NavigationSection: Int, CaseIterable {
    // sidebar order (AJ): Dashboard first, then Notifications
    case dashboard = 0
    case notifications = 1
    case mirror = 2
    case files = 3
    case messages = 4
    case settings = 5

    public var title: String {
        switch self {
        case .mirror: return "Mirror"
        case .dashboard: return "Dashboard"
        case .notifications: return "Notifications"
        case .files: return "Files"
        case .messages: return "Messages"
        case .settings: return "Settings"
        }
    }

    public var iconName: String {
        switch self {
        case .mirror: return "display"
        case .dashboard: return "gauge.with.needle"
        case .notifications: return "bell"
        case .files: return "folder"
        case .messages: return "message"
        case .settings: return "gear"
        }
    }
}

/// Root split view controller managing sidebar navigation and detail content switching.
public final class MainSplitViewController: NSSplitViewController, NSTableViewDataSource, NSTableViewDelegate, NSToolbarDelegate {
    private var connectionManager: ConnectionManager { ConnectionManager.shared }

    private var sidebarItem: NSSplitViewItem?
    private var detailItem: NSSplitViewItem?

    private var sidebarTableView: NSTableView!
    private var currentSection: NavigationSection = .dashboard

    // Cached view controllers
    private lazy var mirrorVC = MirrorViewController()
    private lazy var dashboardVC = DashboardViewController()
    private lazy var notificationVC = NotificationViewController()
    private lazy var fileTransferVC = FileTransferViewController()
    private lazy var messagesVC = MessagesViewController()

    // Toolbar components
    private var statusDotView: NSView!
    private var statusDeviceLabel: NSTextField!
    private var statusBatteryLabel: NSTextField!
    private var connectButton: NSButton!

    public override func viewDidLoad() {
        super.viewDidLoad()
        if ScrcpyToolbar.scrcpyPID() != nil { ScrcpyToolbar.shared.start() } // mirror already open
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        setupSidebar()
        setupDetail()
        setupNotifications()

        sidebarTableView.selectRowIndexes(IndexSet(integer: NavigationSection.dashboard.rawValue), byExtendingSelection: false) // open on Dashboard; mirroring starts only from a Mirror click
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        setupWindowToolbar()
        updateToolbarState()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Sidebar Setup

    private func setupSidebar() {
        let sidebarVC = NSViewController()
        let sidebarView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 600))
        sidebarVC.view = sidebarView

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(scroll)

        sidebarTableView = NSTableView()
        sidebarTableView.headerView = nil
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarCol"))
        sidebarTableView.addTableColumn(col)
        sidebarTableView.dataSource = self
        sidebarTableView.delegate = self
        sidebarTableView.target = self
        sidebarTableView.action = #selector(sidebarClicked(_:))
        sidebarTableView.rowHeight = 40
        scroll.documentView = sidebarTableView

        // Footer for Wizard
        let footer = NSView()
        footer.translatesAutoresizingMaskIntoConstraints = false
        sidebarView.addSubview(footer)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(sep)

        let wizardBtn = NSButton(title: "Setup Guide & Wizard", target: self, action: #selector(openWizardClicked(_:)))
        wizardBtn.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        wizardBtn.isBordered = false
        wizardBtn.alignment = .left
        wizardBtn.font = .systemFont(ofSize: 12)
        wizardBtn.contentTintColor = .secondaryLabelColor
        wizardBtn.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(wizardBtn)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),

            footer.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 44),

            sep.topAnchor.constraint(equalTo: footer.topAnchor),
            sep.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1),

            wizardBtn.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 14),
            wizardBtn.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -14),
            wizardBtn.centerYAnchor.constraint(equalTo: footer.centerYAnchor)
        ])

        let sItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sItem.minimumThickness = 190
        sItem.maximumThickness = 280
        sidebarItem = sItem
        addSplitViewItem(sItem)
    }

    // MARK: - Detail Setup

    private func setupDetail() {
        let dItem = NSSplitViewItem(viewController: dashboardVC)
        dItem.minimumThickness = 500
        detailItem = dItem
        addSplitViewItem(dItem)
    }

    private func selectSection(_ section: NavigationSection) {
        currentSection = section

        if section == .settings {
            SettingsWindowController.shared.showSettings()
            return
        }

        let newVC: NSViewController
        switch section {
        case .mirror: newVC = mirrorVC
        case .dashboard: newVC = dashboardVC
        case .notifications: newVC = notificationVC
        case .files: newVC = fileTransferVC
        case .messages: newVC = messagesVC
        case .settings: newVC = mirrorVC
        }

        // Swap detail view controller
        if let existing = detailItem {
            removeSplitViewItem(existing)
        }
        let item = NSSplitViewItem(viewController: newVC)
        item.minimumThickness = 500
        detailItem = item
        addSplitViewItem(item)
    }

    // Click action (not selection change) so re-clicking Mirror works and startup auto-select doesn't launch.
    @objc private func sidebarClicked(_ sender: NSTableView) {
        guard sender.clickedRow == NavigationSection.mirror.rawValue else { return }
        launchScrcpyMirror()
    }

    func launchScrcpyMirror() {
        ScrcpyToolbar.shared.start() // nav bar follows the scrcpy window once it appears
        if let pid = ScrcpyToolbar.scrcpyPID() {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
            return // already mirroring; never start a second one
        }
        let script = "/Users/anubavkonda/Downloads/Screen mirror/Mirror Phone.command"
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("droidlink-mirror.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh") // the script uses zsh-only syntax
        p.arguments = [script]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        if let log = try? FileHandle(forWritingTo: logURL) {
            p.standardOutput = log
            p.standardError = log
        }
        p.terminationHandler = { proc in
            guard proc.terminationStatus != 0 else { return }
            let tail = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "")
                .split(separator: "\n").suffix(6).joined(separator: "\n")
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Couldn't start phone mirroring"
                alert.informativeText = tail.isEmpty ? "The mirror script exited with code \(proc.terminationStatus)." : tail
                alert.runModal()
            }
        }
        do { try p.run() } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func openWizardClicked(_ sender: NSButton) {
        OnboardingWindowController.shared.showWizard()
    }

    // MARK: - Toolbar Setup

    private func setupWindowToolbar() {
        guard let window = view.window, window.toolbar == nil else { return }

        let toolbar = NSToolbar(identifier: "MainAppToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .sidebarTrackingSeparator,
            .flexibleSpace,
            NSToolbarItem.Identifier("StatusItem"),
            NSToolbarItem.Identifier("ConnectItem")
        ]
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .sidebarTrackingSeparator,
            .flexibleSpace,
            NSToolbarItem.Identifier("StatusItem"),
            NSToolbarItem.Identifier("ConnectItem")
        ]
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == NSToolbarItem.Identifier("StatusItem") {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)

            let pillView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 28))
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
            statusDeviceLabel.translatesAutoresizingMaskIntoConstraints = false
            pillView.addSubview(statusDeviceLabel)

            statusBatteryLabel = NSTextField(labelWithString: "")
            statusBatteryLabel.font = .systemFont(ofSize: 11)
            statusBatteryLabel.textColor = .secondaryLabelColor
            statusBatteryLabel.translatesAutoresizingMaskIntoConstraints = false
            pillView.addSubview(statusBatteryLabel)

            NSLayoutConstraint.activate([
                statusDotView.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 10),
                statusDotView.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
                statusDotView.widthAnchor.constraint(equalToConstant: 8),
                statusDotView.heightAnchor.constraint(equalToConstant: 8),

                statusDeviceLabel.leadingAnchor.constraint(equalTo: statusDotView.trailingAnchor, constant: 8),
                statusDeviceLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),

                statusBatteryLabel.leadingAnchor.constraint(equalTo: statusDeviceLabel.trailingAnchor, constant: 6),
                statusBatteryLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
                statusBatteryLabel.trailingAnchor.constraint(lessThanOrEqualTo: pillView.trailingAnchor, constant: -10)
            ])

            item.view = pillView
            return item
        } else if itemIdentifier == NSToolbarItem.Identifier("ConnectItem") {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            connectButton = NSButton(title: "Connect", target: self, action: #selector(toggleConnection(_:)))
            connectButton.bezelStyle = .rounded
            item.view = connectButton
            return item
        }
        return nil
    }

    private func updateToolbarState() {
        let isConnected = connectionManager.status.isConnectedOrMirroring

        if let dot = statusDotView {
            dot.layer?.backgroundColor = isConnected ? NSColor.systemGreen.cgColor : NSColor.systemRed.cgColor
        }

        if let label = statusDeviceLabel {
            if let info = connectionManager.currentDeviceInfo {
                label.stringValue = info.name
            } else {
                label.stringValue = connectionManager.status.statusTitle
            }
        }

        if let bat = statusBatteryLabel {
            if let info = connectionManager.currentDeviceInfo, isConnected {
                bat.stringValue = "\(info.batteryLevel)% ⚡"
            } else {
                bat.stringValue = ""
            }
        }

        if let btn = connectButton {
            btn.title = isConnected ? "Disconnect" : "Connect"
        }
    }

    @objc private func toggleConnection(_ sender: NSButton) {
        if connectionManager.status.isConnectedOrMirroring {
            connectionManager.disconnect()
        } else {
            if let first = connectionManager.deviceDiscovery.discoveredDevices.first {
                connectionManager.connect(to: first)
            } else if let adbDev = connectionManager.adbService.devices.first(where: { $0.state == .device }) {
                let disc = DiscoveredDevice(
                    id: adbDev.serial,
                    name: adbDev.model ?? "Android Device",
                    model: adbDev.model ?? "Android",
                    transport: .usb,
                    adbSerial: adbDev.serial,
                    isPaired: true
                )
                connectionManager.connect(to: disc)
            } else {
                let alert = NSAlert()
                alert.messageText = "No Devices Found"
                alert.informativeText = "Connect your Android phone via USB with USB Debugging enabled, or ensure it's on the same Wi-Fi network."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateChanged(_:)),
            name: ConnectionManager.didChangeStatusNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateChanged(_:)),
            name: ConnectionManager.didChangeDeviceInfoNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateChanged(_:)),
            name: NotificationBridge.didUpdateNotificationsNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateChanged(_:)),
            name: FileTransferService.didUpdateTransfersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateChanged(_:)),
            name: DeviceDiscovery.didUpdateDevicesNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stateChanged(_:)),
            name: ADBService.didUpdateDevicesNotification,
            object: nil
        )
    }

    @objc private func stateChanged(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateToolbarState()
            self?.sidebarTableView.reloadData()
        }
    }

    // MARK: - NSTableViewDataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return NavigationSection.allCases.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < NavigationSection.allCases.count else { return nil }
        let section = NavigationSection.allCases[row]

        let cellId = NSUserInterfaceItemIdentifier("SidebarRowCell")
        let cell: SidebarItemCell
        if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? SidebarItemCell {
            cell = reused
        } else {
            cell = SidebarItemCell()
            cell.identifier = cellId
        }

        var badgeCount = 0
        if section == .notifications {
            badgeCount = connectionManager.notificationBridge.notifications.filter { !$0.isRead }.count
        } else if section == .files {
            badgeCount = connectionManager.fileTransferService.activeTransfers.count
        }

        cell.configure(section: section, badgeCount: badgeCount)
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = sidebarTableView.selectedRow
        guard row >= 0 && row < NavigationSection.allCases.count else { return }
        selectSection(NavigationSection.allCases[row])
    }
}

// MARK: - Sidebar Item Cell

private final class SidebarItemCell: NSTableCellView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        badgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.wantsLayer = true
        badgeLabel.layer?.backgroundColor = NSColor.droidAccent.cgColor
        badgeLabel.layer?.cornerRadius = 8
        badgeLabel.alignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.isHidden = true
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 20),
            badgeLabel.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    func configure(section: NavigationSection, badgeCount: Int) {
        iconView.image = NSImage(systemSymbolName: section.iconName, accessibilityDescription: section.title)
        iconView.contentTintColor = .secondaryLabelColor
        titleLabel.stringValue = section.title

        if badgeCount > 0 {
            badgeLabel.stringValue = "\(badgeCount)"
            badgeLabel.isHidden = false
        } else {
            badgeLabel.isHidden = true
        }
    }
}
