//
//  ConnectionManager.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import Network
import Observation
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

/// Central connection orchestrator managing TCP/WebSocket channels, heartbeats,
/// and dispatching video/audio/control packets to corresponding services.
@Observable
public final class ConnectionManager: @unchecked Sendable {
    // MARK: - Observable State

    public var status: ConnectionStatus = .disconnected
    public var currentDeviceInfo: DeviceInfo? = nil
    public var latencyMs: Int = 18
    public var settings: MirrorSettings = .default

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
                if let serial = device.adbSerial {
                    // USB / ADB transport
                    try await connectViaAdb(serial: serial)
                } else if let ip = device.ipAddress, let port = device.port {
                    // Wi-Fi transport
                    try await connectViaNetwork(host: ip, port: port)
                } else {
                    // Fallback to mock connect for demonstration
                    simulateMockConnection(device: device)
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
        let localControlPort: UInt16 = 27183
        let localVideoPort: UInt16 = 27184
        let localAudioPort: UInt16 = 27185

        // Forward ADB ports
        try await adbService.forwardPort(local: localControlPort, remote: 27183, serial: serial)
        try await adbService.forwardPort(local: localVideoPort, remote: 27184, serial: serial)
        try await adbService.forwardPort(local: localAudioPort, remote: 27185, serial: serial)

        // Query device telemetry
        let info = (try? await adbService.fetchDeviceInfo(serial: serial)) ?? DeviceInfo.mockPixel8

        DispatchQueue.main.async {
            self.currentDeviceInfo = info
            self.inputForwarder.updateTargetDimensions(width: info.screenWidth, height: info.screenHeight)
        }

        // Establish TCP sockets
        startSockets(host: "127.0.0.1", controlPort: localControlPort, videoPort: localVideoPort, audioPort: localAudioPort, info: info)
    }

    /// Connects directly over local Wi-Fi TCP
    private func connectViaNetwork(host: String, port: UInt16) async throws {
        let info = DeviceInfo.mockGalaxyS24
        DispatchQueue.main.async {
            self.currentDeviceInfo = info
            self.inputForwarder.updateTargetDimensions(width: info.screenWidth, height: info.screenHeight)
        }

        startSockets(host: host, controlPort: port, videoPort: port + 1, audioPort: port + 2, info: info)
    }

    /// Simulates a connected device for UI preview / testing
    public func simulateMockConnection(device: DiscoveredDevice? = nil) {
        let info = DeviceInfo.mockPixel8
        DispatchQueue.main.async {
            self.currentDeviceInfo = info
            self.status = .mirroring(info)
            self.inputForwarder.updateTargetDimensions(width: info.screenWidth, height: info.screenHeight)
            self.audioPlayer.start()
        }
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
            if state == .ready {
                self?.receiveVideoData()
            }
        }
        conn.start(queue: networkQueue)
        self.videoConnection = conn
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

    private func receiveVideoData() {
        videoConnection?.receive(minimumIncompleteLength: 1, maximumLength: 131072) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }

            if let data = data, !data.isEmpty {
                self.videoDecoder.processRawStreamData(data)
            }

            if !isComplete && error == nil {
                self.receiveVideoData()
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
