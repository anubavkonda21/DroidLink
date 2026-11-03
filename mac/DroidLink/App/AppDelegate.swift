//
//  AppDelegate.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

/// Pure AppKit application delegate managing window creation, status bar item,
/// main menu bar, and system sleep/wake events.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public var window: NSWindow?
    private var statusItem: NSStatusItem?

    private var connectionManager: ConnectionManager { ConnectionManager.shared }

    // MARK: - App Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure regular application mode (dock icon and menu bar)
        NSApp.setActivationPolicy(.regular)

        setupMainMenu()
        setupMainWindow()
        setupStatusBarItem()

        // Locate ADB and start discovery
        ADBService.shared.locateADB()

        // Register power events
        registerSleepWakeNotifications()

        // Listen for connection changes to update status item
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectionStateChanged(_:)),
            name: ConnectionManager.didChangeStatusNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectionStateChanged(_:)),
            name: ConnectionManager.didChangeDeviceInfoNotification,
            object: nil
        )

        updateStatusBarMenu()
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
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], // no fullSizeContentView: it hid content under the toolbar
            backing: .buffered,
            defer: false
        )
        win.minSize = NSSize(width: 850, height: 600)
        win.title = "DroidLink"
        win.titleVisibility = .visible
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false

        let rootVC = MainSplitViewController()
        win.contentViewController = rootVC
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
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

        // 4. View Menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let fullScreenItem = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fullScreenItem)
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // 5. Window Menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // 6. Help Menu
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
            button.image = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "DroidLink")
        }
        updateStatusBarMenu()
    }

    private func updateStatusBarMenu() {
        guard let item = statusItem else { return }

        let menu = NSMenu()
        let isConnected = connectionManager.status.isConnectedOrMirroring

        if let info = connectionManager.currentDeviceInfo, isConnected {
            // Update button label
            item.button?.title = " \(info.batteryLevel)%"

            let devHeader = NSMenuItem(title: info.name, action: nil, keyEquivalent: "")
            devHeader.isEnabled = false
            menu.addItem(devHeader)

            let batItem = NSMenuItem(title: "Battery: \(info.batteryFormatted) (\(info.isCharging ? "Charging" : "Discharging"))", action: nil, keyEquivalent: "")
            batItem.isEnabled = false
            menu.addItem(batItem)

            let latItem = NSMenuItem(title: "Latency: \(connectionManager.latencyMs) ms", action: nil, keyEquivalent: "")
            latItem.isEnabled = false
            menu.addItem(latItem)

            menu.addItem(.separator())

            menu.addItem(withTitle: "Open DroidLink Window", action: #selector(openMainWindow(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Phone Home Button", action: #selector(sendHomeButton(_:)), keyEquivalent: "")

            menu.addItem(.separator())

            menu.addItem(withTitle: "Disconnect \(info.name)", action: #selector(disconnectDevice(_:)), keyEquivalent: "")
        } else {
            item.button?.title = ""

            let noDev = NSMenuItem(title: "No Device Connected", action: nil, keyEquivalent: "")
            noDev.isEnabled = false
            menu.addItem(noDev)

            menu.addItem(.separator())

            menu.addItem(withTitle: "Open DroidLink Window", action: #selector(openMainWindow(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Connect Device", action: #selector(connectDevice(_:)), keyEquivalent: "")
            menu.addItem(withTitle: "Refresh Devices", action: #selector(refreshDevices(_:)), keyEquivalent: "")
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "Setup Wizard…", action: #selector(openWizard(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DroidLink", action: #selector(quitApp(_:)), keyEquivalent: "q")

        item.menu = menu
    }

    @objc private func connectionStateChanged(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusBarMenu()
        }
    }

    // MARK: - Menu Actions

    @objc private func openMainWindow(_ sender: Any?) {
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
            alert.informativeText = "Connect your Android phone via USB with USB Debugging enabled."
            alert.alertStyle = .informational
            alert.runModal()
        }
    }

    @objc private func disconnectDevice(_ sender: Any?) {
        connectionManager.disconnect()
    }

    @objc private func refreshDevices(_ sender: Any?) {
        ADBService.shared.refreshDevices()
    }

    @objc private func sendHomeButton(_ sender: Any?) {
        connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .home))
    }

    @objc private func quitApp(_ sender: Any?) {
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
    }

    @objc private func handleSystemWillSleep(_ notification: Notification) {
        connectionManager.disconnect()
    }

    @objc private func handleSystemDidWake(_ notification: Notification) {
        ADBService.shared.refreshDevices()
    }
}
