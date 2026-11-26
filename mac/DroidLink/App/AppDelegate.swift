//
//  AppDelegate.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

/// Pure AppKit application delegate managing the notifications window, status bar item,
/// main menu bar, device pairing, and system sleep/wake events.
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public var window: NSWindow?
    private var statusItem: NSStatusItem?
    private var allowTermination = false

    private var connectionManager: ConnectionManager { ConnectionManager.shared }

    // MARK: - App Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Default auto-connect ON if never explicitly turned off
        if UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.autoConnect) == nil {
            UserDefaults.standard.set(true, forKey: MirrorSettings.StorageKeys.autoConnect)
        }

        NSApp.setActivationPolicy(.regular)

        setupMainMenu()
        setupMainWindow()
        GlossyTrafficLights.installEverywhere()
        setupStatusBarItem()

        ADBService.shared.locateADB()
        DevicePairing.shared.startConnectBrowser()

        registerSleepWakeNotifications()

        for name in [
            ConnectionManager.didChangeStatusNotification,
            ConnectionManager.didChangeDeviceInfoNotification,
            ADBService.didUpdateDevicesNotification,
            DeviceDiscovery.didUpdateDevicesNotification,
            DevicePairing.didChange,
            NotificationBridge.didUpdateNotificationsNotification
        ] {
            NotificationCenter.default.addObserver(self, selector: #selector(connectionStateChanged(_:)), name: name, object: nil)
        }

        updateStatusBarMenu()
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowTermination {
            return .terminateNow
        }
        // Keep DroidLink running in the menu bar on Cmd+Q / Dock Quit so the phone stays connected
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return .terminateCancel
    }

    public func applicationWillTerminate(_ notification: Notification) {
        connectionManager.disconnect()
        ADBService.shared.stopPeriodicDiscovery()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even if window is closed
        return false
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    // MARK: - Main Window Setup

    private func setupMainWindow() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.minSize = NSSize(width: 560, height: 440)
        win.title = "DroidLink Notifications"
        win.titleVisibility = .visible
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false

        let rootVC = MainSplitViewController()
        win.contentViewController = rootVC
        win.delegate = self
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
    }

    public func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        // Hide Dock icon while running quietly in the menu bar receiving notifications
        DispatchQueue.main.async {
            if self.window?.isVisible != true {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: - Main Menu Setup

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 1. Application Menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "DroidLink")
        appMenu.addItem(withTitle: "About DroidLink", action: #selector(openAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DroidLink", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DroidLink", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // 2. File Menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // 3. Edit Menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // 4. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // 5. Help Menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Setup Wizard…", action: #selector(openWizard(_:)), keyEquivalent: "")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Status Bar Item Setup

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "DroidLink Notifications")
        }
        updateStatusBarMenu()
    }

    private func updateStatusBarMenu() {
        guard let item = statusItem else { return }

        let menu = NSMenu()
        let isConnected = connectionManager.status.isConnected
        let unreadCount = connectionManager.notificationBridge.notifications.filter { !$0.isRead }.count

        item.button?.title = unreadCount > 0 ? " \(unreadCount)" : ""

        if let info = connectionManager.currentDeviceInfo, isConnected {
            let devHeader = NSMenuItem(title: "Connected: \(info.name)", action: nil, keyEquivalent: "")
            devHeader.isEnabled = false
            menu.addItem(devHeader)

            menu.addItem(.separator())

            menu.addItem(withTitle: "Open Notifications", action: #selector(openMainWindow(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Disconnect \(info.name)", action: #selector(disconnectDevice(_:)), keyEquivalent: "")
        } else {
            let noDev = NSMenuItem(title: "No Phone Connected", action: nil, keyEquivalent: "")
            noDev.isEnabled = false
            menu.addItem(noDev)

            menu.addItem(.separator())

            menu.addItem(withTitle: "Open Notifications", action: #selector(openMainWindow(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Connect Phone", action: #selector(connectDevice(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Refresh Devices", action: #selector(refreshDevices(_:)), keyEquivalent: "")
        }

        menu.addItem(.separator())
        menu.addItem(devicesMenuItem())
        menu.addItem(withTitle: "Add Phone with QR Code…", action: #selector(addDevice(_:)), keyEquivalent: "")

        menu.addItem(.separator())
        menu.addItem(withTitle: "Setup Wizard…", action: #selector(openWizard(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Completely", action: #selector(quitCompletely(_:)), keyEquivalent: "")

        item.menu = menu
    }

    @objc private func connectionStateChanged(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusBarMenu()
            self?.autoConnectIfIdle()
        }
    }

    private var userDisconnected = false
    private var lastAutoConnect = Date.distantPast
    private var pendingAutoConnect = false

    /// Link to the chosen phone (USB/Wi-Fi ADB, or Bonjour Wi-Fi fallback) whenever nothing is connected.
    private func autoConnectIfIdle() {
        let autoConnect = UserDefaults.standard.object(forKey: MirrorSettings.StorageKeys.autoConnect) as? Bool ?? true
        guard autoConnect, !userDisconnected else { return }
        switch connectionManager.status {
        case .disconnected, .error: break
        default: return
        }

        let elapsed = Date().timeIntervalSince(lastAutoConnect)
        if elapsed <= 10 {
            if !pendingAutoConnect {
                pendingAutoConnect = true
                DispatchQueue.main.asyncAfter(deadline: .now() + (10.5 - elapsed)) { [weak self] in
                    self?.pendingAutoConnect = false
                    self?.autoConnectIfIdle()
                }
            }
            return
        }

        if let serial = connectionManager.adbService.selectedDevice?.serial,
           connectionManager.adbService.devices.contains(where: { $0.serial == serial && $0.state == .device }) {
            lastAutoConnect = Date()
            selectDevice(serial: serial)
            return
        }

        if let wifiDevice = connectionManager.deviceDiscovery.discoveredDevices.first(where: {
            $0.transport == .mdnsWifi && ($0.ipAddress != nil || $0.bonjourServiceName != nil)
        }) {
            lastAutoConnect = Date()
            connectionManager.connect(to: wifiDevice)
        }
    }

    // MARK: - Menu Actions

    @objc private func openMainWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            setupMainWindow()
        } else {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openPreferences(_ sender: Any?) {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func openAbout(_ sender: Any?) {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func openWizard(_ sender: Any?) {
        OnboardingWindowController.shared.showWizard()
    }

    @objc private func connectDevice(_ sender: Any?) {
        if let first = connectionManager.deviceDiscovery.discoveredDevices.first {
            connectionManager.connect(to: first)
        } else {
            connectionManager.adbService.refreshDevices()
            let alert = NSAlert()
            alert.messageText = "No Devices Found"
            alert.informativeText = "Connect your Android phone via USB with USB Debugging enabled, or pair via QR code."
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    // MARK: - Devices

    private func devicesMenuItem() -> NSMenuItem {
        let pairing = DevicePairing.shared
        let sub = NSMenu()
        let online = connectionManager.adbService.devices.filter { $0.state == .device }
        let selected = pairing.selectedSerial ?? connectionManager.adbService.selectedDevice?.serial
        for d in online {
            let name = pairing.rememberedDevice(forAdbSerial: d.serial)?.name ?? d.model?.replacingOccurrences(of: "_", with: " ") ?? d.serial
            let item = NSMenuItem(title: "\(name) (\(d.isWireless ? "Wi-Fi" : "USB"))", action: #selector(pickDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = d.serial
            item.state = d.serial == selected ? .on : .off
            sub.addItem(item)
        }
        let offline = pairing.remembered.filter { r in !online.contains { pairing.rememberedDevice(forAdbSerial: $0.serial) == r } }
        if !offline.isEmpty {
            if !online.isEmpty { sub.addItem(.separator()) }
            for r in offline {
                let item = NSMenuItem(title: "\(r.name) (offline)", action: nil, keyEquivalent: "")
                let forget = NSMenu()
                let f = NSMenuItem(title: "Forget This Phone", action: #selector(forgetDevice(_:)), keyEquivalent: "")
                f.target = self
                f.representedObject = r.serial
                forget.addItem(f)
                item.submenu = forget
                sub.addItem(item)
            }
        }
        if sub.items.isEmpty {
            let none = NSMenuItem(title: "No phones yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        }
        let item = NSMenuItem(title: "Phones", action: nil, keyEquivalent: "")
        item.submenu = sub
        return item
    }

    @objc private func addDevice(_ sender: Any?) {
        AddDeviceWindowController.shared.show()
    }

    @objc private func pickDevice(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String else { return }
        selectDevice(serial: serial)
    }

    @objc private func forgetDevice(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String,
              let r = DevicePairing.shared.remembered.first(where: { $0.serial == serial }) else { return }
        DevicePairing.shared.forget(r)
    }

    /// Makes `serial` the active phone and connects to it.
    func selectDevice(serial: String) {
        userDisconnected = false
        let adb = connectionManager.adbService
        DevicePairing.shared.selectedSerial = serial
        adb.selectedDevice = adb.devices.first { $0.serial == serial } ?? ADBDevice(serial: serial)
        let name = DevicePairing.shared.rememberedDevice(forAdbSerial: serial)?.name ?? adb.selectedDevice?.model ?? serial
        connectionManager.disconnect()
        connectionManager.connect(to: DiscoveredDevice(id: serial, name: name, model: name,
                                                       transport: serial.contains(":") ? .wirelessAdb : .usb,
                                                       adbSerial: serial))
        updateStatusBarMenu()
    }

    @objc private func disconnectDevice(_ sender: Any?) {
        userDisconnected = true
        connectionManager.disconnect()
    }

    @objc private func refreshDevices(_ sender: Any?) {
        ADBService.shared.refreshDevices()
    }

    @objc private func quitCompletely(_ sender: Any?) {
        allowTermination = true
        NSApp.terminate(nil)
    }

    // MARK: - Sleep & Wake Handlers

    private func registerSleepWakeNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillPowerOff(_:)),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
    }

    @objc private func handleSystemWillPowerOff(_ notification: Notification) {
        allowTermination = true
    }

    @objc private func handleSystemWillSleep(_ notification: Notification) {
        connectionManager.disconnect()
    }

    @objc private func handleSystemDidWake(_ notification: Notification) {
        ADBService.shared.refreshDevices()
    }
}
