//
//  ADBService.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

/// Represents an ADB device entry parsed from `adb devices -l`
public struct ADBDevice: Identifiable, Equatable, Hashable {
    public var id: String { serial }
    public var serial: String
    public var state: State
    public var model: String?
    public var device: String?
    public var transportId: String?
    public var isWireless: Bool {
        serial.contains(":")
    }

    public enum State: String, Codable {
        case device
        case unauthorized
        case offline
        case bootloader
        case recovery
        case unknown
    }

    public init(
        serial: String,
        state: State = .device,
        model: String? = nil,
        device: String? = nil,
        transportId: String? = nil
    ) {
        self.serial = serial
        self.state = state
        self.model = model
        self.device = device
        self.transportId = transportId
    }
}

extension ADBService {
    public static let didUpdateDevicesNotification = Notification.Name("ADBServiceDidUpdateDevicesNotification")
    public static let didChangeStateNotification = Notification.Name("ADBServiceDidChangeStateNotification")
}

/// Service managing the Android Debug Bridge (ADB) lifecycle and commands.
public final class ADBService: @unchecked Sendable {
    // MARK: - State Properties

    public var isAdbAvailable: Bool = false {
        didSet { NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self) }
    }
    public var adbPath: String? = nil
    public var devices: [ADBDevice] = [] {
        didSet {
            NotificationCenter.default.post(name: ADBService.didUpdateDevicesNotification, object: self)
            NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self)
        }
    }
    public var selectedDevice: ADBDevice? = nil {
        didSet { NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self) }
    }
    public var isScanning: Bool = false {
        didSet { NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self) }
    }
    public var lastError: String? = nil {
        didSet { NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self) }
    }

    // MARK: - Private State

    private var scanTimer: Timer?
    private let processQueue = DispatchQueue(label: "com.droidlink.adb.queue", qos: .userInitiated)

    // MARK: - Shared Instance

    public static let shared = ADBService()

    // MARK: - Initialization

    public init() {
        locateADB()
        startPeriodicDiscovery()
    }

    deinit {
        stopPeriodicDiscovery()
    }

    // MARK: - ADB Binary Discovery

    /// Searches standard macOS paths for a working ADB executable.
    public func locateADB() {
        let potentialPaths = [
            Bundle.main.path(forResource: "adb", ofType: nil),
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            NSString(string: "~/Library/Android/sdk/platform-tools/adb").expandingTildeInPath,
            "/usr/bin/adb"
        ].compactMap { $0 }

        for path in potentialPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                self.adbPath = path
                self.isAdbAvailable = true
                return
            }
        }

        // Fallback: search system PATH via `which adb`
        if let output = try? executeShellCommand("which adb").trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
            self.adbPath = output
            self.isAdbAvailable = true
        } else {
            self.adbPath = nil
            self.isAdbAvailable = false
        }
    }

    // MARK: - Periodic Device Discovery

    public func startPeriodicDiscovery(interval: TimeInterval = 3.0) {
        stopPeriodicDiscovery()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshDevices()
            self.scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                self?.refreshDevices()
            }
        }
    }

    public func stopPeriodicDiscovery() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - Device Refresh

    public func refreshDevices() {
        guard isAdbAvailable, let adb = adbPath else { return }
        isScanning = true

        processQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let output = try self.runProcess(executable: adb, arguments: ["devices", "-l"])
                let parsedDevices = self.parseDeviceList(output)

                DispatchQueue.main.async {
                    self.devices = parsedDevices
                    self.isScanning = false

                    // Keep the chosen phone; otherwise fall back to the saved choice, then Wi-Fi, then anything.
                    if self.selectedDevice.map({ s in !parsedDevices.contains { $0.serial == s.serial } }) ?? true {
                        let ready = parsedDevices.filter { $0.state == .device }
                        let saved = DevicePairing.shared.selectedSerial
                        let savedIP = saved.flatMap { $0.contains(":") ? String($0.split(separator: ":")[0]) + ":" : nil }
                        self.selectedDevice = ready.first { $0.serial == saved } ?? ready.first { savedIP != nil && $0.serial.hasPrefix(savedIP!) }  // same phone, new Wi-Fi port
                            ?? ready.first { $0.isWireless } ?? parsedDevices.first
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.lastError = error.localizedDescription
                    self.isScanning = false
                }
            }
        }
    }

    // MARK: - Command Execution

    /// Runs an arbitrary ADB command asynchronously
    public func executeADB(_ arguments: [String], serial: String? = nil) async throws -> String {
        guard let adb = adbPath else {
            throw NSError(domain: "ADBService", code: 404, userInfo: [NSLocalizedDescriptionKey: "ADB executable not found"])
        }

        var fullArgs: [String] = []
        if let targetSerial = serial ?? selectedDevice?.serial {
            fullArgs.append(contentsOf: ["-s", targetSerial])
        }
        fullArgs.append(contentsOf: arguments)

        return try await withCheckedThrowingContinuation { continuation in
            processQueue.async {
                do {
                    let result = try self.runProcess(executable: adb, arguments: fullArgs)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fetches rich device telemetry by querying device properties & dumpsys
    public func fetchDeviceInfo(serial: String? = nil) async throws -> DeviceInfo {
        let model = try await executeADB(["shell", "getprop", "ro.product.model"], serial: serial)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let androidVer = try await executeADB(["shell", "getprop", "ro.build.version.release"], serial: serial)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Query Battery
        var batteryLevel = 80
        var isCharging = false
        if let batteryDump = try? await executeADB(["shell", "dumpsys", "battery"], serial: serial) {
            batteryLevel = parseBatteryLevel(from: batteryDump)
            isCharging = batteryDump.contains("status: 2") || batteryDump.contains("status: 5") // Charging or Full
        }

        // Query Storage
        var totalStorage: Int64 = 128_000_000_000
        var freeStorage: Int64 = 64_000_000_000
        if let dfDump = try? await executeADB(["shell", "df", "/data"], serial: serial) {
            let parsed = parseStorage(from: dfDump)
            totalStorage = parsed.total
            freeStorage = parsed.free
        }

        // Query Resolution & Density
        var width = 1080
        var height = 2400
        var dpi = 420
        if let wmSize = try? await executeADB(["shell", "wm", "size"], serial: serial),
           let parsedSize = parseWindowSize(from: wmSize) {
            width = parsedSize.width
            height = parsedSize.height
        }
        if let wmDensity = try? await executeADB(["shell", "wm", "density"], serial: serial),
           let parsedDpi = parseDensity(from: wmDensity) {
            dpi = parsedDpi
        }

        let targetSerial = serial ?? selectedDevice?.serial ?? UUID().uuidString
        let isWireless = targetSerial.contains(":")

        return DeviceInfo(
            id: targetSerial,
            name: model.isEmpty ? "Android Device" : model,
            model: model,
            androidVersion: "Android \(androidVer)",
            batteryLevel: batteryLevel,
            storageTotal: totalStorage,
            storageFree: freeStorage,
            isCharging: isCharging,
            wifiName: isWireless ? "Wi-Fi (Active)" : nil,
            ipAddress: isWireless ? targetSerial.components(separatedBy: ":").first : nil,
            screenWidth: width,
            screenHeight: height,
            screenDpi: dpi,
            connectionType: isWireless ? .wifi : .usb
        )
    }

    /// Sets up port forwarding: Mac localhost:localPort -> Android remotePort
    public func forwardPort(local: UInt16, remote: UInt16, serial: String? = nil) async throws {
        _ = try await executeADB(["forward", "tcp:\(local)", "tcp:\(remote)"], serial: serial)
    }

    /// Removes an existing port forward
    public func removeForward(local: UInt16, serial: String? = nil) async throws {
        _ = try await executeADB(["forward", "--remove", "tcp:\(local)"], serial: serial)
    }

    /// Switches the device into wireless ADB mode listening on port 5555
    public func enableWirelessAdb(port: Int = 5555, serial: String? = nil) async throws {
        _ = try await executeADB(["tcpip", "\(port)"], serial: serial)
    }

    /// Connects to a wireless device via IP address and port
    public func connectWireless(ip: String, port: Int = 5555) async throws -> String {
        let result = try await executeADB(["connect", "\(ip):\(port)"], serial: nil)
        refreshDevices()
        return result
    }

    /// Pushes a local file to the Android device
    public func pushFile(localPath: String, remotePath: String, serial: String? = nil) async throws {
        _ = try await executeADB(["push", localPath, remotePath], serial: serial)
    }

    /// Pulls a remote file from Android to local Mac path
    public func pullFile(remotePath: String, localPath: String, serial: String? = nil) async throws {
        _ = try await executeADB(["pull", remotePath, localPath], serial: serial)
    }

    // MARK: - Output Parsers

    private func parseDeviceList(_ rawOutput: String) -> [ADBDevice] {
        var result: [ADBDevice] = []
        let lines = rawOutput.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("List of devices attached") || trimmed.hasPrefix("*") {
                continue
            }

            let components = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard components.count >= 2 else { continue }

            let serial = components[0]
            let rawState = components[1]
            let state: ADBDevice.State = {
                switch rawState {
                case "device": return .device
                case "unauthorized": return .unauthorized
                case "offline": return .offline
                case "bootloader": return .bootloader
                case "recovery": return .recovery
                default: return .unknown
                }
            }()

            var model: String? = nil
            var device: String? = nil
            var transportId: String? = nil

            for token in components.dropFirst(2) {
                if token.hasPrefix("model:") {
                    model = token.replacingOccurrences(of: "model:", with: "")
                } else if token.hasPrefix("device:") {
                    device = token.replacingOccurrences(of: "device:", with: "")
                } else if token.hasPrefix("transport_id:") {
                    transportId = token.replacingOccurrences(of: "transport_id:", with: "")
                }
            }

            result.append(ADBDevice(
                serial: serial,
                state: state,
                model: model?.replacingOccurrences(of: "_", with: " "),
                device: device,
                transportId: transportId
            ))
        }

        return result
    }

    private func parseBatteryLevel(from dump: String) -> Int {
        for line in dump.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("level:") {
                let parts = trimmed.components(separatedBy: ":")
                if parts.count > 1, let val = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    return val
                }
            }
        }
        return 85
    }

    private func parseStorage(from dump: String) -> (total: Int64, free: Int64) {
        let lines = dump.components(separatedBy: .newlines)
        for line in lines.dropFirst() {
            let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 4, let total1k = Int64(parts[1]), let free1k = Int64(parts[3]) {
                return (total: total1k * 1024, free: free1k * 1024)
            }
        }
        return (total: 128_000_000_000, free: 64_000_000_000)
    }

    private func parseWindowSize(from dump: String) -> (width: Int, height: Int)? {
        let pattern = #"(\d+)x(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(dump.startIndex..<dump.endIndex, in: dump)
        if let match = regex.firstMatch(in: dump, options: [], range: range) {
            let wStr = (dump as NSString).substring(with: match.range(at: 1))
            let hStr = (dump as NSString).substring(with: match.range(at: 2))
            if let w = Int(wStr), let h = Int(hStr) {
                return (width: min(w, h), height: max(w, h))
            }
        }
        return nil
    }

    private func parseDensity(from dump: String) -> Int? {
        let pattern = #"(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(dump.startIndex..<dump.endIndex, in: dump)
        if let match = regex.firstMatch(in: dump, options: [], range: range) {
            let dStr = (dump as NSString).substring(with: match.range(at: 1))
            return Int(dStr)
        }
        return nil
    }

    // MARK: - Process Execution Helper

    private func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = pipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        if process.terminationStatus != 0 {
            let errString = String(data: errData, encoding: .utf8) ?? "Unknown process error"
            throw NSError(domain: "ADBService", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errString])
        }

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func executeShellCommand(_ command: String) throws -> String {
        return try runProcess(executable: "/bin/sh", arguments: ["-c", command])
    }
}
