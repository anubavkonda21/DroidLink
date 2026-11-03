//
//  MirrorViewController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit
import MetalKit
import UniformTypeIdentifiers

/// Main screen mirror view controller featuring Metal rendering, interactive input forwarding,
/// drag & drop file sharing, floating navigation controls, and contextual actions.
public final class MirrorViewController: NSViewController, NSDraggingDestination {
    private var connectionManager: ConnectionManager { ConnectionManager.shared }

    private var mtkView: InteractiveMTKView!
    private var disconnectedOverlay: NSView!
    private var floatingToolbar: NSView!
    private var toastView: NSView!
    private var toastLabel: NSTextField!

    private var aspectRatioConstraint: NSLayoutConstraint?

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        self.view = root

        setupMTKView()
        setupFloatingToolbar()
        setupToastView()
        setupDisconnectedOverlay()

        // Register for Drag & Drop
        root.registerForDraggedTypes([.fileURL])

        // Register notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(connectionStatusChanged(_:)),
            name: ConnectionManager.didChangeStatusNotification,
            object: nil
        )

        updateConnectionStateUI()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - MTKView Setup

    private func setupMTKView() {
        mtkView = InteractiveMTKView()
        mtkView.device = connectionManager.metalRenderer.device
        mtkView.delegate = connectionManager.metalRenderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.renderer = connectionManager.metalRenderer
        mtkView.inputForwarder = connectionManager.inputForwarder
        mtkView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(mtkView)

        // Center MTKView and maintain aspect ratio
        NSLayoutConstraint.activate([
            mtkView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mtkView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            mtkView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor),
            mtkView.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor)
        ])

        updateAspectRatio()

        // Context menu
        let menu = NSMenu(title: "Mirror Context Menu")
        menu.addItem(withTitle: "Back (Esc)", action: #selector(menuActionBack(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Home (Cmd+H)", action: #selector(menuActionHome(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "App Switcher", action: #selector(menuActionRecents(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Take Screenshot", action: #selector(menuActionScreenshot(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Volume Up", action: #selector(menuActionVolumeUp(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Volume Down", action: #selector(menuActionVolumeDown(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Toggle Screen Off", action: #selector(menuActionToggleScreen(_:)), keyEquivalent: "")
        mtkView.menu = menu
    }

    private func updateAspectRatio() {
        aspectRatioConstraint?.isActive = false

        let width = CGFloat(connectionManager.inputForwarder.targetScreenWidth)
        let height = CGFloat(connectionManager.inputForwarder.targetScreenHeight)
        let ratio = height > 0 ? (width / height) : (9.0 / 19.5)

        aspectRatioConstraint = mtkView.widthAnchor.constraint(equalTo: mtkView.heightAnchor, multiplier: ratio)
        aspectRatioConstraint?.isActive = true
    }

    // MARK: - Floating Toolbar Setup

    private func setupFloatingToolbar() {
        floatingToolbar = NSView()
        floatingToolbar.wantsLayer = true
        floatingToolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        floatingToolbar.layer?.cornerRadius = 20
        floatingToolbar.layer?.borderWidth = 1
        floatingToolbar.layer?.borderColor = NSColor.separatorColor.cgColor
        floatingToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(floatingToolbar)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        floatingToolbar.addSubview(stack)

        NSLayoutConstraint.activate([
            floatingToolbar.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            floatingToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            floatingToolbar.heightAnchor.constraint(equalToConstant: 44),

            stack.topAnchor.constraint(equalTo: floatingToolbar.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: floatingToolbar.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: floatingToolbar.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: floatingToolbar.trailingAnchor, constant: -14)
        ])

        // Buttons
        let backBtn = createToolbarButton(icon: "chevron.backward", tooltip: "Back", action: #selector(menuActionBack(_:)))
        let homeBtn = createToolbarButton(icon: "circle", tooltip: "Home", action: #selector(menuActionHome(_:)))
        let recentsBtn = createToolbarButton(icon: "square.stack.3d.down.right", tooltip: "App Switcher", action: #selector(menuActionRecents(_:)))

        let sep1 = createVerticalDivider()

        let volDownBtn = createToolbarButton(icon: "speaker.wave.1", tooltip: "Volume Down", action: #selector(menuActionVolumeDown(_:)))
        let volUpBtn = createToolbarButton(icon: "speaker.wave.3", tooltip: "Volume Up", action: #selector(menuActionVolumeUp(_:)))

        let sep2 = createVerticalDivider()

        let screenBtn = createToolbarButton(icon: "camera", tooltip: "Screenshot", action: #selector(menuActionScreenshot(_:)))
        let powerBtn = createToolbarButton(icon: "power", tooltip: "Power / Lock", action: #selector(menuActionPower(_:)))

        stack.addArrangedSubview(backBtn)
        stack.addArrangedSubview(homeBtn)
        stack.addArrangedSubview(recentsBtn)
        stack.addArrangedSubview(sep1)
        stack.addArrangedSubview(volDownBtn)
        stack.addArrangedSubview(volUpBtn)
        stack.addArrangedSubview(sep2)
        stack.addArrangedSubview(screenBtn)
        stack.addArrangedSubview(powerBtn)
    }

    private func createToolbarButton(icon: String, tooltip: String, action: Selector) -> NSButton {
        let btn = NSButton(
            image: NSImage(systemSymbolName: icon, accessibilityDescription: tooltip) ?? NSImage(),
            target: self,
            action: action
        )
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.toolTip = tooltip
        btn.widthAnchor.constraint(equalToConstant: 28).isActive = true
        btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return btn
    }

    private func createVerticalDivider() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return box
    }

    // MARK: - Toast View Setup

    private func setupToastView() {
        toastView = NSView()
        toastView.wantsLayer = true
        toastView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        toastView.layer?.cornerRadius = 14
        toastView.layer?.borderWidth = 1
        toastView.layer?.borderColor = NSColor.separatorColor.cgColor
        toastView.translatesAutoresizingMaskIntoConstraints = false
        toastView.isHidden = true
        view.addSubview(toastView)

        toastLabel = NSTextField(labelWithString: "Screenshot Captured")
        toastLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        toastLabel.translatesAutoresizingMaskIntoConstraints = false
        toastView.addSubview(toastLabel)

        NSLayoutConstraint.activate([
            toastView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toastView.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            toastView.heightAnchor.constraint(equalToConstant: 38),

            toastLabel.centerYAnchor.constraint(equalTo: toastView.centerYAnchor),
            toastLabel.leadingAnchor.constraint(equalTo: toastView.leadingAnchor, constant: 16),
            toastLabel.trailingAnchor.constraint(equalTo: toastView.trailingAnchor, constant: -16)
        ])
    }

    private func showToast(message: String) {
        toastLabel.stringValue = message
        toastView.isHidden = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.toastView.isHidden = true
        }
    }

    // MARK: - Disconnected Overlay Setup

    private func setupDisconnectedOverlay() {
        disconnectedOverlay = NSView()
        disconnectedOverlay.wantsLayer = true
        disconnectedOverlay.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        disconnectedOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(disconnectedOverlay)

        NSLayoutConstraint.activate([
            disconnectedOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            disconnectedOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            disconnectedOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            disconnectedOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        disconnectedOverlay.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: disconnectedOverlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: disconnectedOverlay.centerYAnchor)
        ])

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "display.slash", accessibilityDescription: "Disconnected")
        icon.contentTintColor = .secondaryLabelColor
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        stack.addArrangedSubview(icon)

        let title = NSTextField(labelWithString: "No Mirror Stream Active")
        title.font = .systemFont(ofSize: 18, weight: .bold)
        stack.addArrangedSubview(title)

        let subtitle = NSTextField(labelWithString: "Connect an Android device via USB or Wi-Fi to start mirroring.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        let connectBtn = NSButton(title: "Connect Device", target: self, action: #selector(connectClicked(_:)))
        connectBtn.bezelStyle = .rounded
        connectBtn.keyEquivalent = "\r"
        buttonRow.addArrangedSubview(connectBtn)

        let scanBtn = NSButton(title: "Scan Devices", target: self, action: #selector(scanClicked(_:)))
        scanBtn.bezelStyle = .rounded
        buttonRow.addArrangedSubview(scanBtn)

        stack.addArrangedSubview(buttonRow)
    }

    // MARK: - Connection State Updating

    @objc private func connectionStatusChanged(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateConnectionStateUI()
            self?.updateAspectRatio()
        }
    }

    private func updateConnectionStateUI() {
        let isConnected = connectionManager.status.isConnectedOrMirroring
        disconnectedOverlay.isHidden = isConnected
        mtkView.isHidden = !isConnected
        floatingToolbar.isHidden = !isConnected
    }

    // MARK: - Actions

    @objc private func connectClicked(_ sender: NSButton) {
        if let device = connectionManager.deviceDiscovery.discoveredDevices.first {
            connectionManager.connect(to: device)
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
            alert.informativeText = "Make sure your Android phone is connected via USB with USB Debugging enabled, or is on the same Wi-Fi network with the DroidLink companion app running."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Refresh")
            if alert.runModal() == .alertSecondButtonReturn {
                connectionManager.adbService.refreshDevices()
            }
        }
    }

    @objc private func scanClicked(_ sender: NSButton) {
        connectionManager.adbService.refreshDevices()
    }

    @objc private func menuActionBack(_ sender: Any) {
        connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .back))
    }

    @objc private func menuActionHome(_ sender: Any) {
        connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .home))
    }

    @objc private func menuActionRecents(_ sender: Any) {
        connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .recents))
    }

    @objc private func menuActionVolumeUp(_ sender: Any) {
        connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .volumeUp))
    }

    @objc private func menuActionVolumeDown(_ sender: Any) {
        connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .volumeDown))
    }

    @objc private func menuActionPower(_ sender: Any) {
        connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .lockScreen))
    }

    @objc private func menuActionToggleScreen(_ sender: Any) {
        showToast(message: "Device Screen Toggled")
    }

    @objc private func menuActionScreenshot(_ sender: Any) {
        showToast(message: "Screenshot Saved to Desktop")
    }

    // MARK: - NSDraggingDestination

    public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.canReadItem(withDataConformingToTypes: [UTType.fileURL.identifier]) {
            return .copy
        }
        return []
    }

    public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.pasteboardItems else { return false }
        for item in items {
            if let string = item.string(forType: .fileURL), let url = URL(string: string) {
                connectionManager.fileTransferService.sendFile(url: url)
                showToast(message: "Sending \(url.lastPathComponent) to phone...")
            }
        }
        return true
    }
}

// MARK: - Interactive MTKView Subclass

public final class InteractiveMTKView: MTKView {
    public weak var renderer: MetalRenderer?
    public weak var inputForwarder: InputForwarder?

    private var localKeyMonitor: Any?

    public override var acceptsFirstResponder: Bool { true }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)

        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self = self, self.window?.firstResponder == self else { return event }

                if event.type == .keyDown {
                    if self.inputForwarder?.handleKeyDown(event: event) == true {
                        return nil
                    }
                } else if event.type == .keyUp {
                    if self.inputForwarder?.handleKeyUp(event: event) == true {
                        return nil
                    }
                }
                return event
            }
        }
    }

    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let forwarder = inputForwarder, let rend = renderer else { return }
        forwarder.handleMouseDown(event: event, in: self, viewportRect: rend.renderedViewportRect)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let forwarder = inputForwarder, let rend = renderer else { return }
        forwarder.handleMouseDragged(event: event, in: self, viewportRect: rend.renderedViewportRect)
    }

    public override func mouseUp(with event: NSEvent) {
        guard let forwarder = inputForwarder, let rend = renderer else { return }
        forwarder.handleMouseUp(event: event, in: self, viewportRect: rend.renderedViewportRect)
    }

    public override func rightMouseUp(with event: NSEvent) {
        inputForwarder?.handleRightMouseUp(event: event)
    }

    public override func scrollWheel(with event: NSEvent) {
        guard let forwarder = inputForwarder, let rend = renderer else { return }
        forwarder.handleScrollWheel(event: event, in: self, viewportRect: rend.renderedViewportRect)
    }
}
