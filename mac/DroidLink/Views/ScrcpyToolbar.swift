import AppKit

/// Floating nav bar that sits under the scrcpy window and sends adb key events.
final class ScrcpyToolbar: NSObject {
    static let shared = ScrcpyToolbar()
    private static let adb = "/opt/homebrew/bin/adb"

    private var panel: NSPanel?
    private var timer: Timer?
    private var pid: pid_t = 0
    private var serial: String?
    private var waitingSince = Date()

    /// Finds a running scrcpy; pgrep because a terminal-started scrcpy may be missing from runningApplications.
    static func scrcpyPID() -> pid_t? {
        run("/usr/bin/pgrep", ["-x", "scrcpy"]).split(separator: "\n").compactMap { pid_t($0) }.first
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> String {
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return "" }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Start following scrcpy (it may take a few seconds to appear after launch).
    func start() {
        waitingSince = Date()
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        tick()
    }

    private func tick() {
        if pid == 0 || kill(pid, 0) != 0 {
            pid = Self.scrcpyPID() ?? 0
            serial = nil
            guard pid != 0 else {
                panel?.orderOut(nil)
                if Date().timeIntervalSince(waitingSince) > 60 { timer?.invalidate(); timer = nil }
                return
            }
            // Reuse the serial the launcher passed to scrcpy.
            let args = Self.run("/bin/ps", ["-o", "args=", "-p", "\(pid)"])
            serial = args.split(separator: " ").first { $0.hasPrefix("--serial=") }.map { String($0.dropFirst(9)) }
        }
        waitingSince = Date()
        guard let frame = scrcpyFrame() else { panel?.orderOut(nil); return } // minimized or hidden
        let p = panel ?? makePanel()
        let size = p.frame.size
        // Below the window; if that's off-screen, overlap the window's bottom edge instead.
        let floor = (NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main)?.visibleFrame.minY ?? 0
        p.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: max(frame.minY - size.height - 8, floor + 8)))
        p.orderFrontRegardless()
    }

    /// scrcpy's window frame in Cocoa coordinates.
    private func scrcpyFrame() -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let info = list.first(where: { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let dict = info[kCGWindowBounds as String] as? NSDictionary,
              let cg = CGRect(dictionaryRepresentation: dict),
              let primary = NSScreen.screens.first else { return nil }
        // CG origin is top-left of the primary screen; Cocoa's is bottom-left.
        return NSRect(x: cg.minX, y: primary.frame.maxY - cg.maxY, width: cg.width, height: cg.height)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.appearance = NSAppearance(named: .darkAqua)

        let bg = NSView()
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.85).cgColor
        bg.layer?.cornerRadius = 20
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor.separatorColor.cgColor

        // Same icons as the in-app mirror toolbar (MirrorViewController).
        let items: [(String, String, [String])] = [
            ("chevron.backward", "Back", ["input", "keyevent", "KEYCODE_BACK"]),
            ("circle", "Home", ["input", "keyevent", "KEYCODE_HOME"]),
            ("square.stack.3d.down.right", "Recent apps", ["input", "keyevent", "KEYCODE_APP_SWITCH"]),
            // Swipe up from the bottom edge (gesture nav: home / app switcher), sized to this phone's screen.
            // adb rejoins the words with spaces, so the phone's shell sees this one script.
            ("chevron.compact.up", "Swipe up", ["s=$(wm size | tail -1 | cut -d: -f2);", "w=${s%x*};", "h=${s#*x};",
                                                "input", "swipe", "$((w/2))", "$((h-10))", "$((w/2))", "$((h/3))", "250"]),
            ("bell", "Notifications", ["cmd", "statusbar", "expand-notifications"]),
            ("", "", []),
            ("speaker.wave.1", "Volume Down", ["input", "keyevent", "KEYCODE_VOLUME_DOWN"]),
            ("speaker.wave.3", "Volume Up", ["input", "keyevent", "KEYCODE_VOLUME_UP"]),
            ("", "", []),
            ("camera", "Screenshot", ["input", "keyevent", "KEYCODE_SYSRQ"]),
            ("power", "Power / Lock", ["input", "keyevent", "KEYCODE_POWER"]),
        ]
        let stack = NSStackView(views: items.map { icon, tip, cmd -> NSView in
            guard !icon.isEmpty else {
                let box = NSBox(); box.boxType = .separator
                box.heightAnchor.constraint(equalToConstant: 18).isActive = true
                return box
            }
            let b = NSButton(image: NSImage(systemSymbolName: icon, accessibilityDescription: tip) ?? NSImage(), target: self, action: #selector(tapped(_:)))
            b.isBordered = false
            b.toolTip = tip
            b.identifier = NSUserInterfaceItemIdentifier(cmd.joined(separator: " "))
            b.widthAnchor.constraint(equalToConstant: 28).isActive = true
            b.heightAnchor.constraint(equalToConstant: 28).isActive = true
            return b
        })
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        bg.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
        ])
        p.contentView = bg
        p.setContentSize(NSSize(width: stack.fittingSize.width + 28, height: 44))
        panel = p
        return p
    }

    @objc private func tapped(_ sender: NSButton) {
        guard let cmd = sender.identifier?.rawValue.split(separator: " ").map(String.init) else { return }
        let known = serial
        DispatchQueue.global(qos: .userInitiated).async {
            // Fallback: first adb device in state "device".
            var s = known
            if s == nil {
                let lines = Self.run(Self.adb, ["devices"]).split(separator: "\n").dropFirst()
                let row = lines.map { $0.split(separator: "\t") }.first { (cols: [Substring]) -> Bool in cols.count == 2 && cols[1] == "device" }
                s = row.map { String($0[0]) }
            }
            guard let s else { return }
            Self.run(Self.adb, ["-s", s, "shell"] + cmd)
        }
    }
}
