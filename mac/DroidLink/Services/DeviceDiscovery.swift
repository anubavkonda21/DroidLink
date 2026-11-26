//
//  DeviceDiscovery.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import Network

/// Unified representation of a detected Android device across USB and Wi-Fi transports.
public struct DiscoveredDevice: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var model: String
    public var transport: TransportType
    public var ipAddress: String?
    public var port: UInt16?
    public var adbSerial: String?
    public var bonjourServiceName: String?
    public var isPaired: Bool
    public var lastSeen: Date

    public enum TransportType: String, Codable, Sendable {
        case usb = "USB Cable"
        case mdnsWifi = "Wi-Fi (Bonjour)"
        case wirelessAdb = "Wireless ADB"

        public var iconName: String {
            switch self {
            case .usb: return "cable.connector"
            case .mdnsWifi: return "bonjour"
            case .wirelessAdb: return "wifi"
            }
        }
    }

    public init(
        id: String,
        name: String,
        model: String,
        transport: TransportType,
        ipAddress: String? = nil,
        port: UInt16? = nil,
        adbSerial: String? = nil,
        bonjourServiceName: String? = nil,
        isPaired: Bool = false,
        lastSeen: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.transport = transport
        self.ipAddress = ipAddress
        self.port = port
        self.adbSerial = adbSerial
        self.bonjourServiceName = bonjourServiceName
        self.isPaired = isPaired
        self.lastSeen = lastSeen
    }
}

extension DeviceDiscovery {
    public static let didUpdateDevicesNotification = Notification.Name("DeviceDiscoveryDidUpdateDevicesNotification")
}

/// Event-driven device discovery via mDNS (Bonjour) and ADB notifications — zero polling timers.
public final class DeviceDiscovery: @unchecked Sendable {
    // MARK: - State

    public var discoveredDevices: [DiscoveredDevice] = [] {
        didSet {
            guard discoveredDevices != oldValue else { return }
            NotificationCenter.default.post(name: DeviceDiscovery.didUpdateDevicesNotification, object: self)
        }
    }
    public var isBrowsing: Bool = false
    public var autoConnectEnabled: Bool = true

    // MARK: - Network Browser

    private var mdnsBrowser: NWBrowser?
    private let discoveryQueue = DispatchQueue(label: "com.droidlink.devicediscovery", qos: .utility)
    private var resolvedMdnsCache: [String: (ip: String, port: UInt16)] = [:]

    // MARK: - Shared Instance

    public static let shared = DeviceDiscovery()

    // MARK: - Initialization

    public init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(adbDevicesUpdated(_:)),
            name: ADBService.didUpdateDevicesNotification,
            object: nil
        )
        startDiscovery()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        stopDiscovery()
    }

    // MARK: - Discovery Controls

    public func startDiscovery() {
        guard !isBrowsing else { return }
        isBrowsing = true

        startMdnsBrowser()
        pollAdbDevices()
    }

    public func stopDiscovery() {
        isBrowsing = false
        stopMdnsBrowser()
    }

    // MARK: - mDNS / Bonjour Browser

    private func startMdnsBrowser() {
        guard mdnsBrowser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_droidlink._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: parameters)

        browser.stateUpdateHandler = { [weak self] newState in
            if case .failed(let error) = newState {
                print("mDNS Browser failed: \(error)")
                self?.stopMdnsBrowser()
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleMdnsResults(results)
        }

        browser.start(queue: discoveryQueue)
        self.mdnsBrowser = browser
    }

    private func stopMdnsBrowser() {
        mdnsBrowser?.cancel()
        mdnsBrowser = nil
    }

    private func handleMdnsResults(_ results: Set<NWBrowser.Result>) {
        var serviceNames: [String] = []
        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                serviceNames.append(name)
            }
        }

        let activeSet = Set(serviceNames)
        resolvedMdnsCache = resolvedMdnsCache.filter { activeSet.contains($0.key) }

        // Publish immediately with bonjourServiceName so NWConnection can connect right away,
        // even before NetService finishes IPv4 resolution.
        publishMdnsDevices(for: serviceNames)

        for name in serviceNames where resolvedMdnsCache[name] == nil {
            Resolver.resolve(type: "_droidlink._tcp.", name: name) { [weak self] ip, port in
                guard let self, let ip, port > 0 else { return }
                self.discoveryQueue.async {
                    self.resolvedMdnsCache[name] = (ip, UInt16(port))
                    self.publishMdnsDevices(for: serviceNames)
                }
            }
        }
    }

    private func publishMdnsDevices(for serviceNames: [String]) {
        let wifiDevices: [DiscoveredDevice] = serviceNames.map { name in
            let resolved = resolvedMdnsCache[name]
            let cleanName = name
                .replacingOccurrences(of: "DroidLink-Companion-", with: "")
                .replacingOccurrences(of: "_", with: " ")
            let id = "bonjour_\(name)"
            return DiscoveredDevice(
                id: id,
                name: cleanName.isEmpty ? name : cleanName,
                model: cleanName,
                transport: .mdnsWifi,
                ipAddress: resolved?.ip,
                port: resolved?.port,
                bonjourServiceName: name,
                isPaired: checkIfPreviouslyPaired(id: id)
            )
        }
        mergeDevices(newDevices: wifiDevices, replacing: [.mdnsWifi])
    }

    // MARK: - Event-Driven ADB Device Sync

    @objc private func adbDevicesUpdated(_ notif: Notification) {
        pollAdbDevices()
    }

    private func pollAdbDevices() {
        let adbDevices = ADBService.shared.devices

        var adbDiscovered: [DiscoveredDevice] = []
        for d in adbDevices where d.state == .device {
            let isWireless = d.isWireless
            let friendlyName = d.model ?? d.serial
            let device = DiscoveredDevice(
                id: d.serial,
                name: friendlyName,
                model: d.model ?? "Android Device",
                transport: isWireless ? .wirelessAdb : .usb,
                adbSerial: d.serial,
                isPaired: true
            )
            adbDiscovered.append(device)
        }

        mergeDevices(newDevices: adbDiscovered, replacing: [.usb, .wirelessAdb])
    }

    // MARK: - Device Merging

    private func mergeDevices(newDevices: [DiscoveredDevice], replacing transports: Set<DiscoveredDevice.TransportType>) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            var updated = self.discoveredDevices.filter { !transports.contains($0.transport) }
            updated.append(contentsOf: newDevices)

            var seen = Set<String>()
            let unique = updated.filter { seen.insert($0.id).inserted }

            let sorted = unique.sorted { d1, d2 in
                let rank: (DiscoveredDevice.TransportType) -> Int = {
                    switch $0 {
                    case .usb: return 0
                    case .wirelessAdb: return 1
                    case .mdnsWifi: return 2
                    }
                }
                if rank(d1.transport) != rank(d2.transport) {
                    return rank(d1.transport) < rank(d2.transport)
                }
                return d1.name < d2.name
            }

            let same = self.discoveredDevices.count == sorted.count && zip(self.discoveredDevices, sorted).allSatisfy { a, b in
                a.id == b.id && a.name == b.name && a.transport == b.transport &&
                a.ipAddress == b.ipAddress && a.port == b.port &&
                a.adbSerial == b.adbSerial && a.bonjourServiceName == b.bonjourServiceName
            }
            if !same {
                self.discoveredDevices = sorted
            }
        }
    }

    // MARK: - Pairing & Pairing History

    private func checkIfPreviouslyPaired(id: String) -> Bool {
        let paired = UserDefaults.standard.stringArray(forKey: "paired_device_ids") ?? []
        return paired.contains(id)
    }

    public func markDeviceAsPaired(id: String) {
        var paired = UserDefaults.standard.stringArray(forKey: "paired_device_ids") ?? []
        if !paired.contains(id) {
            paired.append(id)
            UserDefaults.standard.set(paired, forKey: "paired_device_ids")
        }
        if let idx = discoveredDevices.firstIndex(where: { $0.id == id }) {
            discoveredDevices[idx].isPaired = true
        }
    }
}
