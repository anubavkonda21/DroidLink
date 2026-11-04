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
    private var webcamProcess: Process?
    static let webcamStateChanged = Notification.Name("DroidLinkWebcamStateChanged")
    var isWebcamOn: Bool { webcamProcess?.isRunning == true }

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
        DevicePairing.shared.startConnectBrowser()  // reconnects remembered phones over Wi-Fi

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
        for name in [ADBService.didUpdateDevicesNotification, DevicePairing.didChange] {
            NotificationCenter.default.addObserver(self, selector: #selector(connectionStateChanged(_:)), name: name, object: nil)
        }

        updateStatusBarMenu()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        webcamProcess?.terminate()
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
        menu.addItem(devicesMenuItem())
        menu.addItem(withTitle: "Add Phone with QR Code…", action: #selector(addDevice(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Open Tailscale", action: #selector(openTailscale(_:)), keyEquivalent: "")

        menu.addItem(.separator())
        let camItem = NSMenuItem(title: "Use Phone as Webcam", action: #selector(toggleWebcam(_:)), keyEquivalent: "")
        camItem.state = webcamProcess?.isRunning == true ? .on : .off
        menu.addItem(camItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Setup Wizard…", action: #selector(openWizard(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Preferences…", action: #selector(openPreferences(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit DroidLink", action: #selector(quitApp(_:)), keyEquivalent: "q")

        item.menu = menu
    }

    /// Tailscale links the Mac and phone when they're on different networks.
    @objc private func openTailscale(_ sender: Any?) {
        let ids = ["io.tailscale.ipn.macos", "io.tailscale.ipn.macsys"]  // App Store, standalone
        if let url = ids.lazy.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else if let url = URL(string: "https://tailscale.com/download/mac") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func connectionStateChanged(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateStatusBarMenu()
            self?.autoConnectIfIdle()
        }
    }

    /// Set by the menu's Disconnect so we don't reconnect straight away; picking a phone clears it.
    private var userDisconnected = false
    private var lastAutoConnect = Date.distantPast

    /// Link to the chosen phone on launch and whenever adb sees it again while nothing is connected.
    private func autoConnectIfIdle() {
        guard !userDisconnected else { return }
        switch connectionManager.status {
        case .disconnected, .error: break
        default: return
        }
        guard let serial = connectionManager.adbService.selectedDevice?.serial,
              connectionManager.adbService.devices.contains(where: { $0.serial == serial && $0.state == .device }),
              Date().timeIntervalSince(lastAutoConnect) > 10 else { return }  // a failed attempt sets .error; don't loop on it
        lastAutoConnect = Date()
        selectDevice(serial: serial)
    }

    // MARK: - Menu Actions

    /// Phone camera -> OBS Virtual Camera, via the same kind of launcher script as mirroring.
    @objc func toggleWebcam(_ sender: Any?) {
        if let p = webcamProcess, p.isRunning {
            p.terminate()
            return
        }
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("droidlink-webcam.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["/Users/anubavkonda/Downloads/Screen mirror/Phone Webcam.command"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        if let log = try? FileHandle(forWritingTo: logURL) {
            p.standardOutput = log
            p.standardError = log
        }
        p.terminationHandler = { [weak self] proc in
            let failed = proc.terminationReason == .exit && proc.terminationStatus != 0
            let tail = ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "")
                .split(separator: "\n").suffix(6).joined(separator: "\n")
            DispatchQueue.main.async {
                self?.webcamProcess = nil
                self?.updateStatusBarMenu()
                NotificationCenter.default.post(name: AppDelegate.webcamStateChanged, object: nil)
                guard failed else { return }
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Couldn't start the phone webcam"
                alert.informativeText = tail.isEmpty ? "The webcam script exited with code \(proc.terminationStatus)." : tail
                alert.runModal()
            }
        }
        do {
            try p.run()
            webcamProcess = p
            updateStatusBarMenu()
            NotificationCenter.default.post(name: AppDelegate.webcamStateChanged, object: nil)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

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

    // MARK: - Devices

    /// "Phones" submenu: every phone adb sees (tick = chosen one) and remembered phones that are offline.
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

    /// Makes `serial` the phone everything talks to (mirror, webcam, files, control link) and connects to it.
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
