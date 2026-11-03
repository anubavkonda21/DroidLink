//
//  ConnectionManager.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import Network
import CoreMedia

/// Represents the connection state machine of DroidLink.
public enum ConnectionStatus: Equatable {
    case disconnected
    case discovering
    case connecting(String)
    case connected(DeviceInfo)
    case mirroring(DeviceInfo)
    case reconnecting(attempt: Int)
    case error(String)

    public var isConnectedOrMirroring: Bool {
        switch self {
        case .connected, .mirroring:
            return true
        default:
            return false
        }
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
        case .mirroring(let info):
            return "Mirroring \(info.name)"
        case .reconnecting(let attempt):
            return "Reconnecting (Attempt \(attempt))..."
        case .error(let msg):
            return "Error: \(msg)"
        }
    }
}

extension ConnectionManager {
    public static let didChangeStatusNotification = Notification.Name("ConnectionManagerDidChangeStatusNotification")
    public static let didChangeDeviceInfoNotification = Notification.Name("ConnectionManagerDidChangeDeviceInfoNotification")
    public static let didChangeLatencyNotification = Notification.Name("ConnectionManagerDidChangeLatencyNotification")
    public static let didChangeSettingsNotification = Notification.Name("ConnectionManagerDidChangeSettingsNotification")
}

/// Central connection orchestrator managing TCP/WebSocket channels, heartbeats,
/// and dispatching video/audio/control packets to corresponding services.
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
    public var latencyMs: Int = 18 {
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
    public let videoDecoder: VideoDecoder
    public let metalRenderer: MetalRenderer
    public let audioPlayer: AudioPlayer
    public let clipboardSync: ClipboardSync
    public let notificationBridge: NotificationBridge
    public let fileTransferService: FileTransferService
    public let inputForwarder: InputForwarder
    public let deviceDiscovery: DeviceDiscovery

    // MARK: - Networking State

    private var controlConnection: NWConnection?
    private var videoConnection: NWConnection?
    private var audioConnection: NWConnection?

    private let networkQueue = DispatchQueue(label: "com.droidlink.connectionmanager.network", qos: .userInteractive)
    private var heartbeatTimer: Timer?
    private var reconnectAttempt = 0
    private var maxReconnectAttempts = 5

    // Stream buffers
    private var incomingControlBuffer = Data()

    // MARK: - Shared Instance

    public static let shared = ConnectionManager()

    // MARK: - Initialization

    public init(
        adbService: ADBService = .shared,
        metalRenderer: MetalRenderer = MetalRenderer(),
        videoDecoder: VideoDecoder = VideoDecoder(),
        audioPlayer: AudioPlayer = AudioPlayer(),
        clipboardSync: ClipboardSync = .shared,
        notificationBridge: NotificationBridge = .shared,
        fileTransferService: FileTransferService = .shared,
        inputForwarder: InputForwarder = .shared,
        deviceDiscovery: DeviceDiscovery = .shared
    ) {
        self.adbService = adbService
        self.metalRenderer = metalRenderer
        self.videoDecoder = videoDecoder
        self.audioPlayer = audioPlayer
        self.clipboardSync = clipboardSync
        self.notificationBridge = notificationBridge
        self.fileTransferService = fileTransferService
        self.inputForwarder = inputForwarder
        self.deviceDiscovery = deviceDiscovery

        setupServiceBridges()
    }

    // MARK: - Service Interconnections

    private func setupServiceBridges() {
        // 1. Decoder outputs pixel buffer -> MetalRenderer
        self.videoDecoder.delegate = self

        // 2. Input forwarder sends touch / key / scroll -> Control channel
        self.inputForwarder.onSendTouchEvent = { [weak self] payload in
            self?.sendControlMessage(type: .touchEvent, payload: payload)
        }
        self.inputForwarder.onSendKeyEvent = { [weak self] payload in
            self?.sendControlMessage(type: .keyEvent, payload: payload)
        }
        self.inputForwarder.onSendScrollEvent = { [weak self] payload in
            self?.sendControlMessage(type: .scrollEvent, payload: payload)
        }
        self.inputForwarder.onSendNavigation = { [weak self] payload in
            self?.sendControlMessage(type: .navigation, payload: payload)
        }

        // 3. Local clipboard changed -> Send to Android
        self.clipboardSync.onLocalClipboardChanged = { [weak self] payload in
            self?.sendControlMessage(type: .clipboardSync, payload: payload)
        }

        // 4. Notification actions -> Send to Android
        self.notificationBridge.onReply = { [weak self] payload in
            self?.sendControlMessage(type: .notificationReply, payload: payload)
        }
        self.notificationBridge.onDismiss = { [weak self] payload in
            self?.sendControlMessage(type: .notificationDismiss, payload: payload)
        }
    }

    // MARK: - Connection Lifecycle

    /// Initiates connection to a specific device (via USB ADB or Wi-Fi IP)
    public func connect(to device: DiscoveredDevice) {
        status = .connecting(device.name)
        reconnectAttempt = 0

        Task {
            do {
                // Prefer the Wi-Fi adb serial ("ip:port") so the link survives unplugging the cable
                let ready = adbService.devices.filter { $0.state == .device }
                if let serial = ready.first(where: { $0.serial.contains(":") })?.serial ?? device.adbSerial ?? ready.first?.serial {
                    // USB / ADB transport (preferred)
                    try await connectViaAdb(serial: serial)
                } else if let ip = device.ipAddress, let port = device.port {
                    // Wi-Fi transport
                    try await connectViaNetwork(host: ip, port: port)
                } else {
                    throw NSError(
                        domain: "ConnectionManager",
                        code: 404,
                        userInfo: [NSLocalizedDescriptionKey: "No active connection endpoint found for \(device.name). Please check USB debugging or Wi-Fi network."]
                    )
                }
            } catch {
                DispatchQueue.main.async {
                    self.status = .error(error.localizedDescription)
                }
            }
        }
    }

    /// Connects via ADB port forwarding
    private func connectViaAdb(serial: String) async throws {
        let localControlPort: UInt16 = 8080
        let localVideoPort: UInt16 = 8081
        let localAudioPort: UInt16 = 8083

        // Forward ADB ports (matching Companion app Constants.kt)
        try await adbService.forwardPort(local: localControlPort, remote: 8080, serial: serial)
        try await adbService.forwardPort(local: localVideoPort, remote: 8081, serial: serial)
        try await adbService.forwardPort(local: localAudioPort, remote: 8083, serial: serial)

        // Query real device telemetry
        let info = try await adbService.fetchDeviceInfo(serial: serial)

        DispatchQueue.main.async {
            self.currentDeviceInfo = info
            self.inputForwarder.updateTargetDimensions(width: info.screenWidth, height: info.screenHeight)
        }

        // Establish TCP sockets
        startSockets(host: "127.0.0.1", controlPort: localControlPort, videoPort: localVideoPort, audioPort: localAudioPort, info: info)
    }

    /// Connects directly over local Wi-Fi TCP
    private func connectViaNetwork(host: String, port: UInt16) async throws {
        let info = DeviceInfo(
            id: "\(host):\(port)",
            name: "Android Device (Wi-Fi)",
            model: "Wi-Fi Android Device",
            androidVersion: "Android",
            batteryLevel: 100,
            storageTotal: 256_000_000_000,
            storageFree: 54_000_000_000,
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
            self.inputForwarder.updateTargetDimensions(width: info.screenWidth, height: info.screenHeight)
        }

        startSockets(host: host, controlPort: port, videoPort: port + 1, audioPort: port + 2, info: info)
    }

    private func startSockets(host: String, controlPort: UInt16, videoPort: UInt16, audioPort: UInt16, info: DeviceInfo) {
        let controlEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: controlPort)!)
        let conn = NWConnection(to: controlEndpoint, using: .tcp)

        conn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.status = .mirroring(info)
                    self.startHeartbeat()
                    self.audioPlayer.start()
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

        // Start video and audio sockets
        startVideoSocket(host: host, port: videoPort)
        startAudioSocket(host: host, port: audioPort)
    }

    private func startVideoSocket(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveVideoData(conn, host: host, port: port)
            case .failed:
                self?.retryVideoSocket(after: conn, host: host, port: port)
            default:
                break
            }
        }
        conn.start(queue: networkQueue)
        self.videoConnection = conn
    }

    /// The phone only serves video once the user approves screen capture there, which can be after
    /// the Mac connects; keep retrying while the control channel is up.
    private func retryVideoSocket(after old: NWConnection, host: String, port: UInt16) {
        networkQueue.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self = self, self.controlConnection != nil, self.videoConnection === old else { return }
            old.cancel()
            self.videoDecoder.reset()
            self.startVideoSocket(host: host, port: port)
        }
    }

    private func startAudioSocket(host: String, port: UInt16) {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                self?.receiveAudioData()
            }
        }
        conn.start(queue: networkQueue)
        self.audioConnection = conn
    }

    // MARK: - Disconnection

    public func disconnect() {
        stopHeartbeat()
        controlConnection?.cancel()
        videoConnection?.cancel()
        audioConnection?.cancel()

        controlConnection = nil
        videoConnection = nil
        audioConnection = nil

        audioPlayer.stop()
        videoDecoder.reset()

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
            case .clipboardSync:
                let payload = try envelope.decodePayload(ClipboardPayload.self)
                clipboardSync.receiveRemoteClipboard(payload: payload)
            case .notificationPost:
                let notification = try envelope.decodePayload(AndroidNotification.self)
                notificationBridge.receiveNotification(notification)
            case .fileTransferInit:
                // Phone saved the file in its Downloads; pull it over adb (USB or wireless adb)
                let offer = try envelope.decodePayload(FileTransferInitPayload.self)
                let remotePath = (offer.destinationFolder as NSString).appendingPathComponent(offer.fileName)
                fileTransferService.pullFile(remotePath: remotePath, fileSize: offer.fileSize)
            case .macCommand:
                let command = try envelope.decodePayload(MacCommandPayload.self)
                DispatchQueue.main.async {
                    MacStatus.perform(command.action)
                    // let volume/mute changes show up on the phone right away
                    self.sendControlMessage(type: .macStatus, payload: MacStatus.current())
                }
            case .heartbeat:
                // Calculate RTT
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

    private func receiveVideoData(_ conn: NWConnection, host: String, port: UInt16) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 131072) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.videoDecoder.processRawStreamData(data)
            }

            if isComplete || error != nil {
                self.retryVideoSocket(after: conn, host: host, port: port)
            } else {
                self.receiveVideoData(conn, host: host, port: port)
            }
        }
    }

    private func receiveAudioData() {
        audioConnection?.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.audioPlayer.scheduleRawPCM16(data: data)
            }

            if !isComplete && error == nil {
                self.receiveAudioData()
            }
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
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let envelope = ProtocolMessageEnvelope(type: .heartbeat)
            if let data = try? JSONEncoder().encode(envelope) {
                let framed = ProtocolFramer.frame(data: data)
                self.controlConnection?.send(content: framed, completion: .idempotent)
            }
            self.sendControlMessage(type: .macStatus, payload: MacStatus.current())
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Reconnection Logic

    private func handleConnectionFailure(error: Error?) {
        stopHeartbeat()
        guard reconnectAttempt < maxReconnectAttempts else {
            DispatchQueue.main.async {
                self.status = .disconnected
            }
            return
        }

        reconnectAttempt += 1
        let delay = pow(2.0, Double(reconnectAttempt)) // Exponential backoff: 2s, 4s, 8s...

        DispatchQueue.main.async {
            self.status = .reconnecting(attempt: self.reconnectAttempt)
        }

        networkQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, let device = self.currentDeviceInfo else { return }
            let discDevice = DiscoveredDevice(
                id: device.id,
                name: device.name,
                model: device.model,
                transport: device.connectionType == .usb ? .usb : .wirelessAdb,
                adbSerial: device.id
            )
            self.connect(to: discDevice)
        }
    }
}

// MARK: - VideoDecoderDelegate

extension ConnectionManager: VideoDecoderDelegate {
    public func videoDecoder(_ decoder: VideoDecoder, didOutputPixelBuffer pixelBuffer: CVPixelBuffer, presentationTimestamp: CMTime) {
        metalRenderer.feedPixelBuffer(pixelBuffer)
    }

    public func videoDecoder(_ decoder: VideoDecoder, didFailWithError error: Error) {
        print("Video decoding error: \(error)")
    }
}
