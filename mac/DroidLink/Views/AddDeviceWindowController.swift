//
//  AddDeviceWindowController.swift
//  DroidLink
//
//  Shows the Wireless debugging QR code an Android phone scans to pair with this Mac.
//

import AppKit
import CoreImage

final class AddDeviceWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AddDeviceWindowController()

    private let imageView = NSImageView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Add a Phone"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self

        let steps = NSTextField(wrappingLabelWithString:
            "On the Android phone (Android 11 or newer), on the same Wi-Fi as this Mac:\n" +
            "1. Settings › Developer options › Wireless debugging: turn it on.\n" +
            "2. Tap \"Pair device with QR code\" and scan this code.")
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.alignment = .center
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setAccessibilityLabel("Pairing QR code")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.widthAnchor.constraint(equalToConstant: 260).isActive = true
        imageView.heightAnchor.constraint(equalToConstant: 260).isActive = true
        let newCode = NSButton(title: "New Code", target: self, action: #selector(restart))

        let stack = NSStackView(views: [steps, imageView, statusLabel, newCode])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        restart()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func restart() {
        let pairing = DevicePairing.shared
        pairing.onStatus = { [weak self] in self?.statusLabel.stringValue = $0 }
        pairing.onPaired = { [weak self] serial in
            (NSApp.delegate as? AppDelegate)?.selectDevice(serial: serial)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.close() }
        }
        pairing.startPairing()
        imageView.image = Self.qrImage(pairing.qrPayload)
    }

    func windowWillClose(_ notification: Notification) {
        DevicePairing.shared.stopPairing()
    }

    static func qrImage(_ text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let ci = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: ci)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
