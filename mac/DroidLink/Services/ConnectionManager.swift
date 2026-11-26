//
//  ConnectionManager.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import Network

/// Represents the connection state machine of DroidLink.
public enum ConnectionStatus: Equatable {
    case disconnected
    case discovering
    case connecting(String)
    case connected(DeviceInfo)
    case reconnecting(attempt: Int)
    case error(String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    public var statusTitle: String {
        switch self {
        case .disconnected:
            return "Disconnected"
        case .discovering:
            return "Searching for devices..."
        case .connecting(let name):
            return "Connecting to \(name)..."
        case .connected(let info):
            return "Connected (\(info.name))"
        case .reconnecting(let attempt):
            return "Reconnecting (Attempt \(attempt))..."
        case .error:
            return "Can't reach the phone"
        }
    }
}

extension ConnectionManager {
    public static let didChangeStatusNotification = Notification.Name("ConnectionManagerDidChangeStatusNotification")
    public static let didChangeDeviceInfoNotification = Notification.Name("ConnectionManagerDidChangeDeviceInfoNotification")
    public static let didChangeLatencyNotification = Notification.Name("ConnectionManagerDidChangeLatencyNotification")
    public static let didChangeSettingsNotification = Notification.Name("ConnectionManagerDidChangeSettingsNotification")
}

/// Central connection orchestrator managing the control channel, heartbeats,
/// and routing Android notifications & user replies/dismissals.
public final class ConnectionManager: @unchecked Sendable {
    // MARK: - State

    public var status: ConnectionStatus = .disconnected {
        didSet {
            NotificationCenter.default.post(name: ConnectionManager.didChangeStatusNotification, object: self)
        }
    }
    public var currentDeviceInfo: DeviceInfo? = nil {
        didSet {
            NotificationCenter.default.post(name: ConnectionManager.didChangeDeviceInfoNotification, object: self)
        }
    }
    public var latencyMs: Int = 0 {
        didSet {
            NotificationCenter.default.post(name: ConnectionManager.didChangeLatencyNotification, object: self)
        }
    }
    public var settings: MirrorSettings = .default {
        didSet {
            NotificationCenter.default.post(name: ConnectionManager.didChangeSettingsNotification, object: self)
        }
    }

    // MARK: - Attached Services

    public let adbService: ADBService
    public let notificationBridge: NotificationBridge
    public let deviceDiscovery: DeviceDiscovery

    // MARK: - Networking State

    private var controlConnection: NWConnection?
    private var incomingListener: NWListener?
    private let networkQueue = DispatchQueue(label: "com.droidlink.connectionmanager.network", qos: .userInteractive)
    private var heartbeatTimer: Timer?
    private var reconnectAttempt = 0
    private var lastBonjourServiceName: String?

    private var incomingControlBuffer = Data()

    // MARK: - Shared Instance

    public static let shared = ConnectionManager()

    // MARK: - Initialization

    public init(
        adbService: ADBService = .shared,
        notificationBridge: NotificationBridge = .shared,
        deviceDiscovery: DeviceDiscovery = .shared
    ) {
        self.adbService = adbService
        self.notificationBridge = notificationBridge
        self.deviceDiscovery = deviceDiscovery

        setupServiceBridges()
        startIncomingListener()
    }

    // MARK: - Service Interconnections

    private func setupServiceBridges() {
        self.notificationBridge.onReply = { [weak self] payload in
            self?.sendControlMessage(type: .notificationReply, payload: payload)
        }
        self.notificationBridge.onDismiss = { [weak self] payload in
            self?.sendControlMessage(type: .notificationDismiss, payload: payload)
        }
    }

    // MARK: - Connection Lifecycle

    /// Initiates connection to a specific device (via USB/Wi-Fi ADB, LAN IP, or Bonjour service).
    public func connect(to device: DiscoveredDevice, preserveReconnectAttempt: Bool = false) {
        status = .connecting(device.name)
        if !preserveReconnectAttempt {
            reconnectAttempt = 0
        }

        Task {
            do {
                let ready = adbService.devices.filter { $0.state == .device }
                let chosen = ready.first { $0.serial == device.adbSerial || $0.serial == adbService.selectedDevice?.serial }?.serial
                if let serial = chosen ?? ready.first(where: { $0.serial.contains(":") })?.serial ?? device.adbSerial ?? ready.first?.serial,
                   ready.contains(where: { $0.serial == serial }) {
                    try await connectViaAdb(serial: serial)
                } else if let ip = device.ipAddress, let port = device.port {
                    try await connectViaNetwork(host: ip, port: port, deviceName: device.name, bonjourName: device.bonjourServiceName)
                } else if let svcName = device.bonjourServiceName {
                    connectViaBonjour(serviceName: svcName, deviceName: device.name)
                } else if let wifiFallback = deviceDiscovery.discoveredDevices.first(where: {
                    $0.transport == .mdnsWifi && ($0.ipAddress != nil || $0.bonjourServiceName != nil)
                }) {
                    if let ip = wifiFallback.ipAddress, let port = wifiFallback.port {
                        try await connectViaNetwork(host: ip, port: port, deviceName: wifiFallback.name, bonjourName: wifiFallback.bonjourServiceName)
                    } else if let svcName = wifiFallback.bonjourServiceName {
                        connectViaBonjour(serviceName: svcName, deviceName: wifiFallback.name)
                    }
                } else {
                    throw NSError(
                        domain: "ConnectionManager",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "No active connection endpoint found for \(device.name). Please check USB debugging or Wi-Fi network."]
                    )
                }
            } catch {
                self.adbService.refreshDevices()
                if self.reconnectAttempt > 0 && self.currentDeviceInfo != nil {
                    self.handleConnectionFailure(error: error)
                } else {
                    DispatchQueue.main.async {
                        self.status = .error(error.localizedDescription)
                    }
                }
            }
        }
    }

    /// Connects via ADB port forwarding on the control port (8080)
    private func connectViaAdb(serial: String) async throws {
        let localControlPort: UInt16 = 8080
        try await adbService.forwardPort(local: localControlPort, remote: 8080, serial: serial)

        let info = try await adbService.fetchDeviceInfo(serial: serial)
        lastBonjourServiceName = nil

        DispatchQueue.main.async {
            self.currentDeviceInfo = info
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"), port: NWEndpoint.Port(rawValue: localControlPort)!)
        startControlSocket(endpoint: endpoint, info: info)
    }

    /// Connects directly over local Wi-Fi TCP using resolved IP and port
    private func connectViaNetwork(host: String, port: UInt16, deviceName: String = "Android Phone", bonjourName: String? = nil) async throws {
        lastBonjourServiceName = bonjourName
        let info = DeviceInfo(
            id: "\(host):\(port)",
            name: deviceName,
            model: deviceName,
            androidVersion: "Android",
            batteryLevel: 100,
            storageTotal: 0,
            storageFree: 0,
            isCharging: false,
            wifiName: "Wi-Fi",
            ipAddress: host,
            screenWidth: 1080,
            screenHeight: 2400,
            screenDpi: 420,
            connectionType: .wifi
        )
        DispatchQueue.main.async {
            self.currentDeviceInfo = info
        }

        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        startControlSocket(endpoint: endpoint, info: info)
    }

    /// Connects directly to a Bonjour service endpoint (lets Network.framework handle address resolution)
    private func connectViaBonjour(serviceName: String, deviceName: String) {
        lastBonjourServiceName = serviceName
        let info = DeviceInfo(
            id: "bonjour_\(serviceName)",
            name: deviceName,
            model: deviceName,
            androidVersion: "Android",
            batteryLevel: 100,
            storageTotal: 0,
            storageFree: 0,
            isCharging: false,
            wifiName: "Wi-Fi",
            ipAddress: nil,
            screenWidth: 1080,
            screenHeight: 2400,
            screenDpi: 420,
            connectionType: .wifi
        )
        DispatchQueue.main.async {
            self.currentDeviceInfo = info
        }

        let endpoint = NWEndpoint.service(name: serviceName, type: "_droidlink._tcp", domain: "local.", interface: nil)
        startControlSocket(endpoint: endpoint, info: info)
    }

    private func startControlSocket(endpoint: NWEndpoint, info: DeviceInfo) {
        controlConnection?.stateUpdateHandler = nil
        controlConnection?.cancel()
        controlConnection = nil
        incomingControlBuffer.removeAll()

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 60
        tcpOptions.keepaliveInterval = 15
        tcpOptions.keepaliveCount = 3
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true

        let conn = NWConnection(to: endpoint, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.reconnectAttempt = 0
                    self.status = .connected(info)
                    self.startHeartbeat()
                }
                self.receiveNextControlPacket()
                self.sendHandshake()
            case .failed(let err):
                self.handleConnectionFailure(error: err)
            case .cancelled:
                DispatchQueue.main.async {
                    self.status = .disconnected
                }
            default:
                break
            }
        }

        conn.start(queue: networkQueue)
        self.controlConnection = conn
    }

    // MARK: - Incoming Push Listener (Android screen-off fallback)

    private func startIncomingListener() {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = true
        guard let port = NWEndpoint.Port(rawValue: 8081),
              let listener = try? NWListener(using: params, on: port) else { return }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handleIncomingPushConnection(conn)
        }
        listener.start(queue: networkQueue)
        self.incomingListener = listener
    }

    private func handleIncomingPushConnection(_ conn: NWConnection) {
        var buffer = Data()
        func receiveLoop() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                if let data = data, !data.isEmpty {
                    buffer.append(data)
                    let packets = ProtocolFramer.deframe(buffer: &buffer)
                    for packet in packets {
                        self?.dispatchControlPacket(packet)
                    }
                }
                if isComplete || error != nil {
                    conn.cancel()
                } else {
                    receiveLoop()
                }
            }
        }
        conn.stateUpdateHandler = { state in
            if case .ready = state {
                receiveLoop()
            } else if case .failed = state {
                conn.cancel()
            }
        }
        conn.start(queue: networkQueue)
    }

    // MARK: - Disconnection

    public func disconnect() {
        stopHeartbeat()
        controlConnection?.stateUpdateHandler = nil
        controlConnection?.cancel()
        controlConnection = nil
        incomingControlBuffer.removeAll()
        lastBonjourServiceName = nil

        status = .disconnected
        currentDeviceInfo = nil
    }

    // MARK: - Packet Ingestion & Dispatch

    private func receiveNextControlPacket() {
        controlConnection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.incomingControlBuffer.append(data)
                let packets = ProtocolFramer.deframe(buffer: &self.incomingControlBuffer)
                for packet in packets {
                    self.dispatchControlPacket(packet)
                }
            }

            if isComplete {
                self.handleConnectionFailure(error: nil)
            } else if error == nil {
                self.receiveNextControlPacket()
            }
        }
    }

    private func dispatchControlPacket(_ data: Data) {
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(ProtocolMessageEnvelope.self, from: data)

            switch envelope.type {
            case .notificationPost:
                let notification = try envelope.decodePayload(AndroidNotification.self)
                notificationBridge.receiveNotification(notification)
            case .heartbeat:
                let now = Date().timeIntervalSince1970
                let rtt = Int((now - envelope.timestamp) * 1000)
                DispatchQueue.main.async {
                    self.latencyMs = max(5, rtt)
                }
            default:
                break
            }
        } catch {
            print("Failed to dispatch control packet: \(error)")
        }
    }

    // MARK: - Outgoing Control Messages

    public func sendControlMessage<T: Codable>(type: MessageType, payload: T) {
        do {
            let data = try ProtocolMessageEnvelope.encode(type: type, payload: payload)
            let framed = ProtocolFramer.frame(data: data)
            controlConnection?.send(content: framed, completion: .contentProcessed({ error in
                if let error = error {
                    print("Failed to send control message \(type): \(error)")
                }
            }))
        } catch {
            print("Failed to encode payload: \(error)")
        }
    }

    private func sendHandshake() {
        let handshake = HandshakePayload()
        sendControlMessage(type: .handshake, payload: handshake)
    }

    // MARK: - Heartbeat & Keepalive

    private func startHeartbeat() {
        stopHeartbeat()
        let timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let envelope = ProtocolMessageEnvelope(type: .heartbeat)
            if let data = try? JSONEncoder().encode(envelope) {
                let framed = ProtocolFramer.frame(data: data)
                self.controlConnection?.send(content: framed, completion: .idempotent)
            }
        }
        timer.tolerance = 15.0
        heartbeatTimer = timer
        timer.fire()
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Reconnection Logic

    private func handleConnectionFailure(error: Error?) {
        stopHeartbeat()
        controlConnection?.stateUpdateHandler = nil
        controlConnection?.cancel()
        controlConnection = nil
        incomingControlBuffer.removeAll()
        adbService.refreshDevices()

        reconnectAttempt += 1
        let delay = min(30, pow(2.0, Double(reconnectAttempt)))

        DispatchQueue.main.async {
            self.status = .reconnecting(attempt: self.reconnectAttempt)
        }

        networkQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, let device = self.currentDeviceInfo else { return }

            // If USB cable was unplugged, switch immediately to any discovered Wi-Fi / Bonjour device
            if let wifiFallback = self.deviceDiscovery.discoveredDevices.first(where: {
                $0.transport == .wirelessAdb || $0.transport == .mdnsWifi
            }), !self.adbService.devices.contains(where: { $0.serial == device.id && $0.state == .device }) {
                self.connect(to: wifiFallback, preserveReconnectAttempt: true)
                return
            }

            let discDevice: DiscoveredDevice
            if device.connectionType == .wifi {
                let port: UInt16? = device.ipAddress != nil
                    ? UInt16(device.id.split(separator: ":").last.flatMap { UInt16($0) } ?? 8080)
                    : nil
                discDevice = DiscoveredDevice(
                    id: device.id,
                    name: device.name,
                    model: device.model,
                    transport: .mdnsWifi,
                    ipAddress: device.ipAddress,
                    port: port,
                    bonjourServiceName: self.lastBonjourServiceName
                )
            } else {
                discDevice = DiscoveredDevice(
                    id: device.id,
                    name: device.name,
                    model: device.model,
                    transport: device.connectionType == .usb ? .usb : .wirelessAdb,
                    adbSerial: device.id
                )
            }
            self.connect(to: discDevice, preserveReconnectAttempt: true)
        }
    }
}
