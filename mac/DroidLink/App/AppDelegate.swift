//
//  AppDelegate.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import AppKit

/// Application delegate managing system sleep/wake lifecycle, ADB initialization,
/// and graceful shutdown of stream connections.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - App Lifecycle

    public func applicationDidFinishLaunching(_ notification: Notification) {
        print("DroidLink macOS launched successfully.")

        // Verify ADB binary availability
        ADBService.shared.locateADB()

        // Register for system power events (sleep / wake)
        registerSleepWakeNotifications()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        print("DroidLink terminating. Performing cleanup...")

        // Disconnect active streams and clean up ADB port forwardings
        ConnectionManager.shared.disconnect()
        ADBService.shared.stopPeriodicDiscovery()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even if window is closed
        return false
    }

    // MARK: - Sleep & Wake Handlers

    private func registerSleepWakeNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter

        notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleSystemWillSleep(_ notification: Notification) {
        print("macOS going to sleep. Pausing mirror streams...")
        ConnectionManager.shared.disconnect()
    }

    @objc private func handleSystemDidWake(_ notification: Notification) {
        print("macOS woke from sleep. Scanning for Android devices...")
        ADBService.shared.refreshDevices()
    }
}
