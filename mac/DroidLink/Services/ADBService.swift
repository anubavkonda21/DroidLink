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
        didSet {
            guard isAdbAvailable != oldValue else { return }
            NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self)
        }
    }
    public var adbPath: String? = nil
    public var devices: [ADBDevice] = [] {
        didSet {
            guard devices != oldValue else { return }
            NotificationCenter.default.post(name: ADBService.didUpdateDevicesNotification, object: self)
            NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self)
        }
    }
    public var selectedDevice: ADBDevice? = nil {
        didSet {
            guard selectedDevice != oldValue else { return }
            NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self)
        }
    }
    public var isScanning: Bool = false {
        didSet {
            guard isScanning != oldValue else { return }
            NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self)
        }
    }
    public var lastError: String? = nil {
        didSet {
            guard lastError != oldValue else { return }
            NotificationCenter.default.post(name: ADBService.didChangeStateNotification, object: self)
        }
    }

    // MARK: - Private State

    private var scanTimer: Timer?
    private var lastRefresh = Date.distantPast
    private let processQueue = DispatchQueue(label: "com.droidlink.adb.queue", qos: .utility)

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

        if let output = try? executeShellCommand("which adb").trimmingCharacters(in: .whitespacesAndNewlines),
           !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
            self.adbPath = output
            self.isAdbAvailable = true
        } else {
            self.adbPath = nil
            self.isAdbAvailable = false
        }
    }

    // MARK: - Low-Power Periodic Device Discovery

    /// Checks ADB conservatively so macOS can keep CPU and USB/Wi-Fi asleep in the background:
    /// every 10s when disconnected, or every 45s when a phone is already connected.
    public func startPeriodicDiscovery(interval: TimeInterval = 10.0) {
        stopPeriodicDiscovery()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.refreshDevices()
            self.scanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self else { return }
                let minWait: TimeInterval = self.devices.contains(where: { $0.state == .device }) ? 45.0 : interval
                if Date().timeIntervalSince(self.lastRefresh) < minWait { return }
                self.refreshDevices()
            }
            self.scanTimer?.tolerance = 4.0
        }
    }

    public func stopPeriodicDiscovery() {
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - Device Refresh

    public func refreshDevices() {
        guard isAdbAvailable, let adb = adbPath, !isScanning else { return }
        isScanning = true
        lastRefresh = Date()

        processQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                let output = try self.runProcess(executable: adb, arguments: ["devices", "-l"])
                let parsedDevices = self.parseDeviceList(output)

                DispatchQueue.main.async {
                    self.devices = parsedDevices
                    self.isScanning = false

                    if self.selectedDevice.map({ s in !parsedDevices.contains { $0.serial == s.serial } }) ?? true {
                        let ready = parsedDevices.filter { $0.state == .device }
                        let saved = DevicePairing.shared.selectedSerial
                        let savedIP = saved.flatMap { $0.contains(":") ? String($0.split(separator: ":")[0]) + ":" : nil }
                        self.selectedDevice = ready.first { $0.serial == saved }
                            ?? ready.first { savedIP != nil && $0.serial.hasPrefix(savedIP!) }
                            ?? ready.first { $0.isWireless }
                            ?? parsedDevices.first
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

    /// Lightweight single-command identity lookup (no heavy dumpsys battery/storage/screen queries).
    public func fetchDeviceInfo(serial: String? = nil) async throws -> DeviceInfo {
        let model = try await executeADB(["shell", "getprop", "ro.product.model"], serial: serial)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let targetSerial = serial ?? selectedDevice?.serial ?? UUID().uuidString
        let isWireless = targetSerial.contains(":")

        return DeviceInfo(
            id: targetSerial,
            name: model.isEmpty ? "Android Phone" : model,
            model: model,
            androidVersion: "Android",
            batteryLevel: 100,
            storageTotal: 0,
            storageFree: 0,
            isCharging: false,
            wifiName: isWireless ? "Wi-Fi" : nil,
            ipAddress: isWireless ? targetSerial.components(separatedBy: ":").first : nil,
            screenWidth: 1080,
            screenHeight: 2400,
            screenDpi: 420,
            connectionType: isWireless ? .wifi : .usb
        )
    }

    public func forwardPort(local: UInt16, remote: UInt16, serial: String? = nil) async throws {
        _ = try await executeADB(["forward", "tcp:\(local)", "tcp:\(remote)"], serial: serial)
    }

    public func removeForward(local: UInt16, serial: String? = nil) async throws {
        _ = try await executeADB(["forward", "--remove", "tcp:\(local)"], serial: serial)
    }

    public func connectWireless(ip: String, port: Int = 5555) async throws -> String {
        let result = try await executeADB(["connect", "\(ip):\(port)"], serial: nil)
        refreshDevices()
        return result
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
