//
//  NotificationBridge.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation
import AppKit
import UserNotifications

extension NotificationBridge {
    public static let didUpdateNotificationsNotification = Notification.Name("NotificationBridgeDidUpdateNotificationsNotification")
}

/// Manages incoming notifications from Android, integrates with macOS Notification Center,
/// and routes user replies back to the Android companion app.
public final class NotificationBridge: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    // MARK: - State

    public var notifications: [AndroidNotification] = [] {
        didSet {
            NotificationCenter.default.post(name: NotificationBridge.didUpdateNotificationsNotification, object: self)
        }
    }
    public var mutedAppPackages: Set<String> = []
    public var isSoundEnabled: Bool = true
    public var isSyncEnabled: Bool = true

    // MARK: - Outgoing Action Callbacks

    public var onReply: ((NotificationReplyPayload) -> Void)?
    public var onDismiss: ((NotificationDismissPayload) -> Void)?

    // MARK: - Notification Category & Action IDs

    private let categoryId = "DROIDLINK_NOTIFICATION"
    private let replyActionId = "DROIDLINK_REPLY_ACTION"
    private let dismissActionId = "DROIDLINK_DISMISS_ACTION"

    // MARK: - Shared Instance

    public static let shared = NotificationBridge()

    // MARK: - Initialization

    public override init() {
        super.init()
        setupNotificationCategories()
        requestAuthorization()
        loadMutedPackages()

    }

    // MARK: - UNUserNotificationCenter Setup

    private var isNotificationCenterAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func requestAuthorization() {
        guard isNotificationCenterAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Notification authorization failed: \(error)")
            }
            // Phone notifications are useless if macOS blocks our banners; say so instead of failing silently
            center.getNotificationSettings { settings in
                guard settings.authorizationStatus != .authorized else { return }
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Turn on notifications for DroidLink"
                    alert.informativeText = "macOS is blocking DroidLink's notifications, so phone notifications and calls can't appear. In the next window, select DroidLink and switch on Allow Notifications."
                    alert.addButton(withTitle: "Open Notification Settings")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn,
                       let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func setupNotificationCategories() {
        guard isNotificationCenterAvailable else { return }
        let replyAction = UNTextInputNotificationAction(
            identifier: replyActionId,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Type your reply..."
        )

        let dismissAction = UNNotificationAction(
            identifier: dismissActionId,
            title: "Dismiss",
            options: [.destructive]
        )

        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [replyAction, dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Remote Ingestion (Android -> Mac)

    /// Processes an incoming notification posted by the Android companion app
    public func receiveNotification(_ notification: AndroidNotification) {
        guard isSyncEnabled else { return }

        if let pkg = notification.appPackage, mutedAppPackages.contains(pkg) {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Insert into local in-app list
            if let idx = self.notifications.firstIndex(where: { $0.id == notification.id }) {
                self.notifications[idx] = notification
            } else {
                self.notifications.insert(notification, at: 0)
            }

            self.postMacSystemNotification(notification)
            if notification.isSilent == true { self.pulseTrackpadForCall() }
        }
    }

    /// Macs have no vibration motor; the Force Touch trackpad's haptic pulse is the closest thing.
    /// It is only felt while a finger is resting on the trackpad.
    private func pulseTrackpadForCall() {
        for i in 0..<6 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.35) {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
    }

    /// Handles batch notification synchronization from Android
    public func receiveBatchNotifications(_ list: [AndroidNotification]) {
        guard isSyncEnabled else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.notifications = list.filter { item in
                guard let pkg = item.appPackage else { return true }
                return !self.mutedAppPackages.contains(pkg)
            }
        }
    }

    // MARK: - Native macOS Notification Posting

    private func postMacSystemNotification(_ notification: AndroidNotification) {
        guard isNotificationCenterAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(notification.appName) — \(notification.title)"
        content.body = notification.body
        content.categoryIdentifier = categoryId
        content.userInfo = [
            "notificationId": notification.id,
            "canReply": notification.canReply,
            "appPackage": notification.appPackage ?? ""
        ]

        if isSoundEnabled && notification.isSilent != true {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to deliver native notification: \(error)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show banner and play sound even while app is active
        completionHandler([.banner, .sound])
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let notificationId = userInfo["notificationId"] as? String else {
            completionHandler()
            return
        }

        if response.actionIdentifier == replyActionId,
           let textResponse = response as? UNTextInputNotificationResponse {
            let replyText = textResponse.userText
            sendReply(notificationId: notificationId, replyText: replyText)
        } else if response.actionIdentifier == dismissActionId {
            dismissNotification(id: notificationId)
        }

        completionHandler()
    }

    // MARK: - User Actions

    public func sendReply(notificationId: String, replyText: String) {
        let payload = NotificationReplyPayload(notificationId: notificationId, replyText: replyText)
        onReply?(payload)

        // Mark as read in local list
        DispatchQueue.main.async {
            if let idx = self.notifications.firstIndex(where: { $0.id == notificationId }) {
                self.notifications[idx].isRead = true
            }
        }
    }

    public func dismissNotification(id: String) {
        let payload = NotificationDismissPayload(notificationId: id)
        onDismiss?(payload)

        if isNotificationCenterAvailable {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
        }

        DispatchQueue.main.async {
            self.notifications.removeAll(where: { $0.id == id })
        }
    }

    public func clearAll() {
        if isNotificationCenterAvailable {
            UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        }
        DispatchQueue.main.async {
            self.notifications.removeAll()
        }
    }

    // MARK: - App Filter Management

    public func toggleMute(appPackage: String) {
        if mutedAppPackages.contains(appPackage) {
            mutedAppPackages.remove(appPackage)
        } else {
            mutedAppPackages.insert(appPackage)
        }
        saveMutedPackages()
    }

    private func saveMutedPackages() {
        let array = Array(mutedAppPackages)
        UserDefaults.standard.set(array, forKey: "muted_notification_packages")
    }

    private func loadMutedPackages() {
        if let array = UserDefaults.standard.stringArray(forKey: "muted_notification_packages") {
            mutedAppPackages = Set(array)
        }
    }
}
