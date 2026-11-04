//
//  ClipboardSync.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import AppKit

extension ClipboardSync {
    public static let didUpdateClipboardNotification = Notification.Name("ClipboardSyncDidUpdateClipboardNotification")
}

/// Service managing bidirectional clipboard synchronization and OTP auto-detection.
public final class ClipboardSync: @unchecked Sendable {
    // MARK: - State

    public var isAutoSyncEnabled: Bool = true
    public var isOtpAutoForwardEnabled: Bool = true
    public var history: [ClipboardItem] = [] {
        didSet {
            NotificationCenter.default.post(name: ClipboardSync.didUpdateClipboardNotification, object: self)
        }
    }
    public var lastCopiedItem: ClipboardItem? = nil {
        didSet {
            NotificationCenter.default.post(name: ClipboardSync.didUpdateClipboardNotification, object: self)
        }
    }
    public var detectedOtp: String? = nil {
        didSet {
            NotificationCenter.default.post(name: ClipboardSync.didUpdateClipboardNotification, object: self)
        }
    }

    // MARK: - Outgoing Callback

    /// Closure invoked when a local macOS clipboard update needs to be sent to Android
    public var onLocalClipboardChanged: ((ClipboardPayload) -> Void)?

    // MARK: - Internal State

    private var pasteboardTimer: Timer?
    private var lastObservedChangeCount: Int = 0
    private var isUpdatingFromRemote: Bool = false
    private let syncQueue = DispatchQueue(label: "com.droidlink.clipboardsync", qos: .utility)

    // MARK: - Shared Instance

    public static let shared = ClipboardSync()

    // MARK: - Initialization

    public init() {
        self.lastObservedChangeCount = NSPasteboard.general.changeCount
        loadSettings()
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Monitoring

    public func startMonitoring(interval: TimeInterval = 0.5) {
        stopMonitoring()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lastObservedChangeCount = NSPasteboard.general.changeCount
            self.pasteboardTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.checkPasteboardChange()
            }
            self.pasteboardTimer?.tolerance = 0.2 // lets macOS batch wakeups with other timers
        }
    }

    public func stopMonitoring() {
        pasteboardTimer?.invalidate()
        pasteboardTimer = nil
    }

    // MARK: - Pasteboard Checking (Mac -> Android)

    private func checkPasteboardChange() {
        guard isAutoSyncEnabled else { return }

        let currentChangeCount = NSPasteboard.general.changeCount
        guard currentChangeCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = currentChangeCount

        // If the change count was incremented because we received an Android payload, suppress feedback loop
        if isUpdatingFromRemote {
            isUpdatingFromRemote = false
            return
        }

        let pasteboard = NSPasteboard.general

        // 1. Check for plain text
        if let stringValue = pasteboard.string(forType: .string), !stringValue.isEmpty {
            let item = ClipboardItem.create(content: .text(stringValue), source: .mac)
            recordHistory(item)

            let payload = ClipboardPayload(text: stringValue)
            onLocalClipboardChanged?(payload)
            return
        }

        // 2. Check for image
        if let imgData = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) {
            let item = ClipboardItem.create(content: .image(imgData), source: .mac)
            recordHistory(item)

            let base64 = imgData.base64EncodedString()
            let payload = ClipboardPayload(imageBase64: base64)
            onLocalClipboardChanged?(payload)
        }
    }

    // MARK: - Remote Ingestion (Android -> Mac)

    /// Receives remote clipboard data forwarded from Android and updates local pasteboard
    public func receiveRemoteClipboard(payload: ClipboardPayload) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isUpdatingFromRemote = true

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()

            if let text = payload.text, !text.isEmpty {
                pasteboard.setString(text, forType: .string)
                self.lastObservedChangeCount = pasteboard.changeCount

                let item = ClipboardItem.create(content: .text(text), source: .android)
                self.recordHistory(item)

                if item.isOTP, let code = item.otpCode {
                    self.detectedOtp = code
                    if self.isOtpAutoForwardEnabled {
                        // Keep OTP highlighted in UI
                        print("Detected OTP from Android: \(code)")
                    }
                }
            } else if let b64 = payload.imageBase64, let data = Data(base64Encoded: b64) {
                if let image = NSImage(data: data), let tiff = image.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                    self.lastObservedChangeCount = pasteboard.changeCount

                    let item = ClipboardItem.create(content: .image(data), source: .android)
                    self.recordHistory(item)
                }
            }
        }
    }

    // MARK: - History & Storage

    private func recordHistory(_ item: ClipboardItem) {
        // Prevent immediate duplicates
        if let last = history.first, last.content == item.content {
            return
        }

        history.insert(item, at: 0)
        lastCopiedItem = item

        // Limit history to 50 items
        if history.count > 50 {
            history.removeLast()
        }
    }

    public func clearHistory() {
        history.removeAll()
        lastCopiedItem = nil
        detectedOtp = nil
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: MirrorSettings.StorageKeys.autoSyncClipboard) != nil {
            isAutoSyncEnabled = defaults.bool(forKey: MirrorSettings.StorageKeys.autoSyncClipboard)
        }
        if defaults.object(forKey: MirrorSettings.StorageKeys.otpAutoForward) != nil {
            isOtpAutoForwardEnabled = defaults.bool(forKey: MirrorSettings.StorageKeys.otpAutoForward)
        }
    }
}
