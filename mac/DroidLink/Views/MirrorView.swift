//
//  MirrorView.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import SwiftUI
import MetalKit
import UniformTypeIdentifiers

/// Main screen mirror view featuring Metal rendering, interactive input forwarding,
/// drag & drop file sharing, floating navigation controls, and contextual actions.
public struct MirrorView: View {
    // MARK: - Environment & State

    @Environment(ConnectionManager.self) private var connectionManager
    @State private var isHoveringControls: Bool = false
    @State private var isRecording: Bool = false
    @State private var showingScreenshotToast: Bool = false
    @State private var lastScreenshot: NSImage? = nil

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if connectionManager.status.isConnectedOrMirroring {
                // Interactive Metal Stream View
                MetalStreamRepresentable(
                    renderer: connectionManager.metalRenderer,
                    inputForwarder: connectionManager.inputForwarder
                )
                .aspectRatio(contentMode: .fit)
                .contextMenu {
                    contextMenuContent
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                }

                // Floating Remote Navigation Bar (Auto-hiding or hovering)
                VStack {
                    Spacer()
                    floatingToolbar
                        .padding(.bottom, 16)
                }

                // Screenshot captured notification toast
                if showingScreenshotToast {
                    VStack {
                        screenshotToast
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 20)
                        Spacer()
                    }
                }
            } else {
                // Disconnected Placeholder / Connection Prompt
                disconnectedOverlay
            }
        }
    }

    // MARK: - Floating Toolbar

    private var floatingToolbar: some View {
        HStack(spacing: 12) {
            // Android Back Button
            toolbarButton(icon: "chevron.backward", tooltip: "Back (Esc / Right-Click)") {
                connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .back))
            }

            // Android Home Button
            toolbarButton(icon: "circle", tooltip: "Home (Cmd+H)") {
                connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .home))
            }

            // Android Recents / App Switcher
            toolbarButton(icon: "square.stack.3d.down.right", tooltip: "App Switcher") {
                connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .recents))
            }

            Divider()
                .frame(height: 18)

            // Volume Controls
            toolbarButton(icon: "speaker.wave.1", tooltip: "Volume Down") {
                connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .volumeDown))
            }
            toolbarButton(icon: "speaker.wave.3", tooltip: "Volume Up") {
                connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .volumeUp))
            }

            Divider()
                .frame(height: 18)

            // Screenshot Action
            toolbarButton(icon: "camera.fill", tooltip: "Take Screenshot") {
                takeScreenshot()
            }

            // Screen Off / Lock
            toolbarButton(icon: "lock.fill", tooltip: "Lock Device Screen") {
                connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .lockScreen))
            }

            // FPS & Latency Counter Pill
            HStack(spacing: 4) {
                Text("\(Int(connectionManager.metalRenderer.currentFps)) FPS")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.green)

                Text("•")
                    .foregroundStyle(.secondary)

                Text("\(connectionManager.latencyMs)ms")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
    }

    private func toolbarButton(icon: String, tooltip: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            takeScreenshot()
        } label: {
            Label("Take Screenshot", systemImage: "camera")
        }

        Button {
            isRecording.toggle()
        } label: {
            Label(isRecording ? "Stop Recording" : "Record Screen", systemImage: isRecording ? "stop.circle.fill" : "record.circle")
        }

        Divider()

        Button {
            connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .home))
        } label: {
            Label("Go to Home", systemImage: "house")
        }

        Button {
            connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .recents))
        } label: {
            Label("Open App Switcher", systemImage: "square.stack.3d.down.right")
        }

        Button {
            connectionManager.inputForwarder.onSendNavigation?(NavigationPayload(target: .notifications))
        } label: {
            Label("Pull Notification Shade", systemImage: "bell")
        }

        Divider()

        Button {
            connectionManager.disconnect()
        } label: {
            Label("Disconnect", systemImage: "power")
        }
    }

    // MARK: - Disconnected Overlay

    private var disconnectedOverlay: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: "smartphone")
                    .font(.system(size: 46))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 8) {
                Text("No Device Connected")
                    .font(.title2.bold())

                Text("Connect your Android phone via USB cable with USB Debugging enabled, or select a device on your local Wi-Fi.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            HStack(spacing: 14) {
                Button {
                    if let firstDevice = connectionManager.deviceDiscovery.discoveredDevices.first {
                        connectionManager.connect(to: firstDevice)
                    } else {
                        connectionManager.simulateMockConnection()
                    }
                } label: {
                    Label("Connect Device", systemImage: "bolt.fill")
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    connectionManager.adbService.refreshDevices()
                } label: {
                    Label("Scan for Devices", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(40)
    }

    // MARK: - Screenshot Toast

    private var screenshotToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Screenshot Captured")
                    .font(.caption.bold())
                Text("Saved to Downloads and copied to clipboard")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let img = lastScreenshot {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 48)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .shadow(radius: 10)
    }

    // MARK: - Actions

    private func takeScreenshot() {
        connectionManager.metalRenderer.captureScreenshot { image in
            guard let image = image else { return }
            self.lastScreenshot = image

            // Copy to clipboard
            NSPasteboard.general.clearContents()
            if let tiff = image.tiffRepresentation {
                NSPasteboard.general.setData(tiff, forType: .tiff)
            }

            // Save to Downloads folder
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd-HHmmss"
                let timestamp = formatter.string(from: Date())
                let filename = "DroidLink-\(timestamp).png"
                let downloadDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
                let fileURL = downloadDir.appendingPathComponent(filename)
                try? pngData.write(to: fileURL)
            }

            withAnimation {
                showingScreenshotToast = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                withAnimation {
                    showingScreenshotToast = false
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didHandle = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        if let url = item as? URL {
                            connectionManager.fileTransferService.sendFile(url: url)
                        }
                        return
                    }
                    connectionManager.fileTransferService.sendFile(url: url)
                }
                didHandle = true
            }
        }
        return didHandle
    }
}

// MARK: - NSViewRepresentable wrapping MTKView

public struct MetalStreamRepresentable: NSViewRepresentable {
    let renderer: MetalRenderer
    let inputForwarder: InputForwarder

    public func makeNSView(context: Context) -> InteractiveMTKView {
        let mtkView = InteractiveMTKView()
        mtkView.device = renderer.device
        mtkView.delegate = renderer
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        mtkView.renderer = renderer
        mtkView.inputForwarder = inputForwarder

        return mtkView
    }

    public func updateNSView(_ nsView: InteractiveMTKView, context: Context) {
        nsView.renderer = renderer
        nsView.inputForwarder = inputForwarder
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

        // Monitor local keyboard events
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                guard let self = self, self.window?.firstResponder == self else { return event }

                if event.type == .keyDown {
                    if self.inputForwarder?.handleKeyDown(event: event) == true {
                        return nil // Consumed
                    }
                } else if event.type == .keyUp {
                    if self.inputForwarder?.handleKeyUp(event: event) == true {
                        return nil // Consumed
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

    // MARK: - Mouse Event Overrides

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
