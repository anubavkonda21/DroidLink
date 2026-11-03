//
//  DevicePairing.swift
//  DroidLink
//
//  QR pairing with Android 11+ Wireless debugging, the chosen phone, and remembered phones.
//

import Foundation
import Network

/// A phone that paired with this Mac before. `serial` is ro.serialno, which the phone also
/// puts in its `_adb-tls-connect._tcp` instance name ("adb-<serial>-xxxx").
struct RememberedDevice: Codable, Hashable {
    var serial: String
    var name: String
    var ip: String
}

final class DevicePairing {
    static let shared = DevicePairing()
    static let didChange = Notification.Name("DevicePairingDidChange")

    private let defaults = UserDefaults.standard
    /// Read by Mirror Phone.command / Phone Webcam.command so they use the chosen phone.
    static let selectedSerialFile = URL(fileURLWithPath: "/Users/anubavkonda/Downloads/Screen mirror/.phone_serial")
    static let companionPackage = "com.droidlink.companion"
    static let companionAPK = "/Users/anubavkonda/Downloads/Screen mirror/DroidLink/android/app/build/outputs/apk/debug/app-debug.apk"

    // MARK: - Remembered + chosen phone

    var remembered: [RememberedDevice] {
        get { (defaults.data(forKey: "rememberedDevices")).flatMap { try? JSONDecoder().decode([RememberedDevice].self, from: $0) } ?? [] }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: "rememberedDevices")
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    /// adb serial of the phone the user picked ("ip:port" or a USB serial).
    var selectedSerial: String? {
        get { defaults.string(forKey: "selectedAdbSerial") }
        set {
            defaults.set(newValue, forKey: "selectedAdbSerial")
            try? (newValue ?? "").write(to: Self.selectedSerialFile, atomically: true, encoding: .utf8)
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }

    func forget(_ device: RememberedDevice) {
        remembered.removeAll { $0.serial == device.serial }
        _ = adb(["disconnect", device.ip])
    }

    /// The remembered phone behind an adb serial: USB serials match directly, Wi-Fi ones by IP.
    func rememberedDevice(forAdbSerial s: String) -> RememberedDevice? {
        remembered.first { $0.serial == s || s.hasPrefix($0.ip + ":") }
    }

    // MARK: - QR pairing

    private(set) var pairingName = ""
    private(set) var pairingPassword = ""
    /// Android's "Pair device with QR code" reads this format.
    var qrPayload: String { "WIFI:T:ADB;S:\(pairingName);P:\(pairingPassword);;" }
    var onStatus: ((String) -> Void)?
    /// Called on the main queue with the new adb serial once the phone is paired, connected and the app started.
    var onPaired: ((String) -> Void)?
    private var pairingActive = false
    private var pairedIP: String?

    func startPairing() {
        let chars = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        pairingName = "droidlink-" + String((0..<6).map { _ in chars.randomElement()! })
        pairingPassword = String(format: "%06d", Int.random(in: 0..<1_000_000))
        pairingActive = true
        pairedIP = nil
        status("Waiting for the phone to scan the code…")
        tryResolvePairing()
    }

    func stopPairing() { pairingActive = false }

    /// The phone advertises `_adb-tls-pairing._tcp` under our QR name once it has scanned the code.
    private func tryResolvePairing() {
        guard pairingActive else { return }
        let name = pairingName
        Resolver.resolve(type: "_adb-tls-pairing._tcp.", name: name) { [weak self] ip, port in
            guard let self, self.pairingActive, name == self.pairingName else { return }
            guard let ip else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.tryResolvePairing() }
                return
            }
            self.status("Pairing with \(ip)…")
            DispatchQueue.global(qos: .userInitiated).async {
                let out = self.adb(["pair", "\(ip):\(port)", self.pairingPassword])
                DispatchQueue.main.async {
                    guard out.contains("Successfully paired") else {
                        self.status("Pairing failed: \(out.trimmingCharacters(in: .whitespacesAndNewlines)). Tap Pair device with QR code again.")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.tryResolvePairing() }
                        return
                    }
                    self.pairedIP = ip
                    self.status("Paired. Connecting…")
                    if let b = self.connectBrowser { self.handleConnectResults(b.browseResults) }
                }
            }
        }
    }

    // MARK: - Connect browser (new pairings + remembered phones)

    private var connectBrowser: NWBrowser?
    private var connecting = Set<String>()

    /// Watches `_adb-tls-connect._tcp` and connects the phone we just paired, plus any remembered phone that is offline.
    func startConnectBrowser() {
        guard connectBrowser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: "_adb-tls-connect._tcp", domain: "local."), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async { self?.handleConnectResults(results) }
        }
        b.start(queue: .main)
        connectBrowser = b
        // Phones that are already advertising don't re-trigger the handler, so re-check now and then.
        Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            guard let self, let b = self.connectBrowser else { return }
            self.handleConnectResults(b.browseResults)
        }
    }

    private func handleConnectResults(_ results: Set<NWBrowser.Result>) {
        let online = Set(adbOnlineSerials())
        for r in results {
            guard case .service(let name, _, _, _) = r.endpoint, !connecting.contains(name) else { continue }
            let known = remembered.first { name.hasPrefix("adb-\($0.serial)-") }
            guard pairedIP != nil || known != nil else { continue }
            if let known, online.contains(where: { $0 == known.serial || $0.hasPrefix(known.ip + ":") }), pairedIP == nil { continue }
            connecting.insert(name)
            Resolver.resolve(type: "_adb-tls-connect._tcp.", name: name) { [weak self] ip, port in
                guard let self else { return }
                guard let ip, known != nil || ip == self.pairedIP else { self.connecting.remove(name); return }
                let isNew = ip == self.pairedIP
                if isNew { self.pairedIP = nil }
                DispatchQueue.global(qos: .userInitiated).async {
                    let serial = "\(ip):\(port)"
                    _ = self.adb(["connect", serial])
                    let ok = self.adb(["-s", serial, "get-state"]).contains("device")
                    if ok { self.finishConnect(serial: serial, ip: ip, isNew: isNew) }
                    DispatchQueue.main.async {
                        self.connecting.remove(name)
                        if !ok && isNew { self.pairedIP = ip; self.status("Couldn't connect to \(ip), retrying…") }
                    }
                }
            }
        }
    }

    /// Runs off the main queue: remember the phone, make sure the companion app is on it, and start it.
    private func finishConnect(serial: String, ip: String, isNew: Bool) {
        let prop = { (p: String) in self.adb(["-s", serial, "shell", "getprop", p]).trimmingCharacters(in: .whitespacesAndNewlines) }
        let hwSerial = prop("ro.serialno")
        let model = [prop("ro.product.manufacturer").capitalized, prop("ro.product.model")].filter { !$0.isEmpty }.joined(separator: " ")
        let entry = RememberedDevice(serial: hwSerial.isEmpty ? ip : hwSerial, name: model.isEmpty ? ip : model, ip: ip)

        if isNew {
            if !adb(["-s", serial, "shell", "pm", "path", Self.companionPackage]).contains("package:"),
               FileManager.default.fileExists(atPath: Self.companionAPK) {
                DispatchQueue.main.async { self.status("Installing DroidLink on \(entry.name)…") }
                _ = adb(["-s", serial, "install", "-r", Self.companionAPK])
            }
            _ = adb(["-s", serial, "shell", "monkey", "-p", Self.companionPackage, "-c", "android.intent.category.LAUNCHER", "1"])
        }
        DispatchQueue.main.async {
            var list = self.remembered.filter { $0.serial != entry.serial }
            list.append(entry)
            self.remembered = list
            ADBService.shared.refreshDevices()
            if isNew {
                self.pairingActive = false
                self.status("Connected to \(entry.name).")
                self.onPaired?(serial)
            }
        }
    }

    // MARK: - Helpers

    private func status(_ s: String) { DispatchQueue.main.async { self.onStatus?(s) } }

    func adbOnlineSerials() -> [String] {
        ADBService.shared.devices.filter { $0.state == .device }.map(\.serial)
    }

    /// Runs adb without ADBService's automatic `-s <selected>`, which `pair`/`connect` must not get.
    @discardableResult
    func adb(_ args: [String]) -> String {
        guard let path = ADBService.shared.adbPath else { return "adb not found" }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return error.localizedDescription }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Resolves a Bonjour service name to an IPv4 address and port without connecting to it
/// (connecting to the pairing port would use up the phone's one pairing attempt).
private final class Resolver: NSObject, NetServiceDelegate {
    private static var live = Set<Resolver>()
    private let service: NetService
    private let done: (String?, Int) -> Void

    static func resolve(type: String, name: String, done: @escaping (String?, Int) -> Void) {
        DispatchQueue.main.async {
            let r = Resolver(service: NetService(domain: "local.", type: type, name: name), done: done)
            live.insert(r)
            r.service.delegate = r
            r.service.resolve(withTimeout: 3)
        }
    }

    private init(service: NetService, done: @escaping (String?, Int) -> Void) {
        self.service = service
        self.done = done
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        // Called again as more addresses arrive; the first call may hold only IPv6 ones.
        guard let ip = (sender.addresses ?? []).lazy.compactMap(Self.ipv4).first else { return }
        finish(ip, sender.port)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) { finish(nil, 0) }

    private func finish(_ ip: String?, _ port: Int) {
        guard Self.live.remove(self) != nil else { return }
        service.stop()
        done(port > 0 ? ip : nil, port)
    }

    private static func ipv4(_ data: Data) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard raw.count >= MemoryLayout<sockaddr_in>.size,
                  raw.load(as: sockaddr.self).sa_family == sa_family_t(AF_INET) else { return nil }
            var addr = raw.load(as: sockaddr_in.self).sin_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            return inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)).map { String(cString: $0) }
        }
    }
}
