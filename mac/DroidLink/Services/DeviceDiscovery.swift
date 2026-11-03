//
//  DeviceDiscovery.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import Network
import Observation

/// Unified representation of a detected Android device across USB and Wi-Fi transports.
public struct DiscoveredDevice: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var model: String
    public var transport: TransportType
    public var ipAddress: String?
    public var port: UInt16?
    public var adbSerial: String?
    public var isPaired: Bool
    public var lastSeen: Date

    public enum TransportType: String, Codable, Sendable {
        case usb = "USB Cable"
        case mdnsWifi = "Wi-Fi (Bonjour)"
        case wirelessAdb = "Wireless ADB"

        public var iconName: String {
            switch self {
            case .usb:
                return "cable.connector"
            case .mdnsWifi:
                return "bonjour"
            case .wirelessAdb:
                return "wifi"
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
        self.isPaired = isPaired
        self.lastSeen = lastSeen
    }
}

/// Service that discovers Android devices concurrently via mDNS (Bonjour) and ADB USB/TCP.
@Observable
public final class DeviceDiscovery: @unchecked Sendable {
    // MARK: - Observable State

    public var discoveredDevices: [DiscoveredDevice] = []
    public var isBrowsing: Bool = false
    public var autoConnectEnabled: Bool = true

    // MARK: - Network Browser

    private var mdnsBrowser: NWBrowser?
    private let discoveryQueue = DispatchQueue(label: "com.droidlink.devicediscovery", qos: .utility)
    private var adbObserverTimer: Timer?

    // MARK: - Shared Instance

    public static let shared = DeviceDiscovery()

    // MARK: - Initialization

    public init() {
        startDiscovery()
    }

    deinit {
        stopDiscovery()
    }

    // MARK: - Discovery Controls

    public func startDiscovery() {
        guard !isBrowsing else { return }
        isBrowsing = true

        startMdnsBrowser()
        startAdbDevicePolling()
    }

    public func stopDiscovery() {
        isBrowsing = false
        stopMdnsBrowser()
        stopAdbDevicePolling()
    }

    // MARK: - mDNS / Bonjour Browser

    private func startMdnsBrowser() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        // Browsing for DroidLink Companion service: _droidlink._tcp
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_droidlink._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: parameters)

        browser.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .ready:
                break
            case .failed(let error):
                print("mDNS Browser failed: \(error)")
                self?.stopMdnsBrowser()
            case .cancelled:
                break
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, changes in
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
        var wifiDevices: [DiscoveredDevice] = []

        for result in results {
            if case .service(let name, _, _, _) = result.endpoint {
                let id = "bonjour_\(name)"
                let device = DiscoveredDevice(
                    id: id,
                    name: name,
                    model: "Android Companion",
                    transport: .mdnsWifi,
                    isPaired: checkIfPreviouslyPaired(id: id)
                )
                wifiDevices.append(device)
            }
        }

        mergeDevices(newDevices: wifiDevices, transport: .mdnsWifi)
    }

    // MARK: - ADB Device Polling

    private func startAdbDevicePolling() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pollAdbDevices()
            self.adbObserverTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                self?.pollAdbDevices()
            }
        }
    }

    private func stopAdbDevicePolling() {
        adbObserverTimer?.invalidate()
        adbObserverTimer = nil
    }

    private func pollAdbDevices() {
        let adb = ADBService.shared
        let adbDevices = adb.devices

        var usbDevices: [DiscoveredDevice] = []
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
            usbDevices.append(device)
        }

        mergeDevices(newDevices: usbDevices, transport: .usb)
    }

    // MARK: - Device Merging

    private func mergeDevices(newDevices: [DiscoveredDevice], transport: DiscoveredDevice.TransportType) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Retain devices from other transports, replace current transport devices
            var updated = self.discoveredDevices.filter { $0.transport != transport }
            updated.append(contentsOf: newDevices)

            // Deduplicate by id
            var seen = Set<String>()
            self.discoveredDevices = updated.filter { seen.insert($0.id).inserted }
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
