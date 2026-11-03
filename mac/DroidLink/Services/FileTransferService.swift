//
//  FileTransferService.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

extension FileTransferService {
    public static let didUpdateTransfersNotification = Notification.Name("FileTransferServiceDidUpdateTransfersNotification")
}

/// Service managing file transfers between macOS and Android via ADB or Wi-Fi TCP streams.
public final class FileTransferService: @unchecked Sendable {
    // MARK: - State

    public var activeTransfers: [FileTransferItem] = [] {
        didSet {
            NotificationCenter.default.post(name: FileTransferService.didUpdateTransfersNotification, object: self)
        }
    }
    public var transferHistory: [FileTransferItem] = [] {
        didSet {
            NotificationCenter.default.post(name: FileTransferService.didUpdateTransfersNotification, object: self)
        }
    }
    public var isAutoOrganizeEnabled: Bool = true
    public var defaultDownloadPath: String = {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? "/Users/Shared"
    }()

    // MARK: - Queue & Concurrency

    private let transferQueue = DispatchQueue(label: "com.droidlink.filetransfer", qos: .utility)
    private var runningTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Shared Instance

    public static let shared = FileTransferService()

    // MARK: - Initialization

    public init() {
        loadSettings()
    }

    // MARK: - Send Files (Mac -> Android)

    /// Enqueues local file URLs for pushing to Android device
    public func sendFiles(urls: [URL], remoteFolder: String? = nil) {
        for url in urls {
            sendFile(url: url, remoteFolder: remoteFolder)
        }
    }

    /// Enqueues a single file URL for pushing to Android device
    public func sendFile(url: URL, remoteFolder: String? = nil) {
        let fileName = url.lastPathComponent
        let fileSize: Int64 = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0

        let destinationFolder = remoteFolder ?? determineAndroidTargetFolder(for: url)
        let destinationPath = "\(destinationFolder)/\(fileName)"

        let item = FileTransferItem(
            fileName: fileName,
            fileSize: fileSize,
            direction: .toAndroid,
            status: .queued,
            localPath: url.path,
            remotePath: destinationPath,
            startDate: Date()
        )

        DispatchQueue.main.async {
            self.activeTransfers.append(item)
            self.startNextTransferIfNeeded()
        }
    }

    // MARK: - Receive Files (Android -> Mac)

    /// Enqueues a file pull from the Android device to the Mac
    public func pullFile(remotePath: String, fileSize: Int64 = 0) {
        let fileName = (remotePath as NSString).lastPathComponent
        let localDir = isAutoOrganizeEnabled ? determineMacFolder(for: fileName) : defaultDownloadPath
        let localFilePath = (localDir as NSString).appendingPathComponent(fileName)

        let item = FileTransferItem(
            fileName: fileName,
            fileSize: fileSize,
            direction: .toMac,
            status: .queued,
            localPath: localFilePath,
            remotePath: remotePath,
            startDate: Date()
        )

        DispatchQueue.main.async {
            self.activeTransfers.append(item)
            self.startNextTransferIfNeeded()
        }
    }

    // MARK: - Queue Execution

    private func startNextTransferIfNeeded() {
        guard let item = activeTransfers.first(where: { $0.status == .queued }) else { return }

        let itemId = item.id
        updateTransferStatus(id: itemId, status: .transferring)

        let task = Task { [weak self] in
            guard let self = self else { return }
            await self.executeTransfer(item: item)
        }
        runningTasks[itemId] = task
    }

    private func executeTransfer(item: FileTransferItem) async {
        let adb = ADBService.shared

        do {
            guard adb.isAdbAvailable else {
                throw NSError(domain: "FileTransfer", code: -2, userInfo: [NSLocalizedDescriptionKey: "adb not found"])
            }
            guard let localPath = item.localPath, let remotePath = item.remotePath else {
                throw NSError(domain: "FileTransfer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid paths"])
            }
            // Real adb result decides success; errors now surface as a failed transfer
            if item.direction == .toAndroid {
                try await adb.pushFile(localPath: localPath, remotePath: remotePath)
            } else {
                try await adb.pullFile(remotePath: remotePath, localPath: localPath)
            }
            // Completed successfully
            DispatchQueue.main.async {
                self.completeTransfer(id: item.id)
            }
        } catch {
            DispatchQueue.main.async {
                self.failTransfer(id: item.id, error: error.localizedDescription)
            }
        }
    }

    // MARK: - Status Updates

    private func updateTransferStatus(id: UUID, status: FileTransferItem.Status) {
        if let idx = activeTransfers.firstIndex(where: { $0.id == id }) {
            activeTransfers[idx].status = status
        }
    }

    private func completeTransfer(id: UUID) {
        runningTasks.removeValue(forKey: id)
        if let idx = activeTransfers.firstIndex(where: { $0.id == id }) {
            var item = activeTransfers[idx]
            item.status = .completed
            item.progress = 1.0
            item.bytesTransferred = item.fileSize
            item.completionDate = Date()
            activeTransfers.remove(at: idx)
            transferHistory.insert(item, at: 0)
        }
        startNextTransferIfNeeded()
    }

    private func failTransfer(id: UUID, error: String) {
        runningTasks.removeValue(forKey: id)
        if let idx = activeTransfers.firstIndex(where: { $0.id == id }) {
            var item = activeTransfers[idx]
            item.status = .failed
            item.errorMessage = error
            activeTransfers.remove(at: idx)
            transferHistory.insert(item, at: 0)
        }
        startNextTransferIfNeeded()
    }

    public func cancelTransfer(id: UUID) {
        runningTasks[id]?.cancel()
        runningTasks.removeValue(forKey: id)
        if let idx = activeTransfers.firstIndex(where: { $0.id == id }) {
            var item = activeTransfers[idx]
            item.status = .cancelled
            activeTransfers.remove(at: idx)
            transferHistory.insert(item, at: 0)
        }
        startNextTransferIfNeeded()
    }

    public func clearHistory() {
        transferHistory.removeAll()
    }

    // MARK: - Auto Organize Folders

    private func determineAndroidTargetFolder(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp", "gif":
            return "/sdcard/Pictures"
        case "mp4", "mkv", "mov":
            return "/sdcard/Movies"
        case "mp3", "flac", "m4a", "wav":
            return "/sdcard/Music"
        case "pdf", "docx", "xlsx", "pptx", "txt":
            return "/sdcard/Documents"
        case "apk":
            return "/sdcard/Download"
        default:
            return "/sdcard/Download"
        }
    }

    private func determineMacFolder(for fileName: String) -> String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        let fileManager = FileManager.default

        switch ext {
        case "jpg", "jpeg", "png", "heic", "webp", "gif":
            return fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first?.path ?? defaultDownloadPath
        case "mp4", "mkv", "mov":
            return fileManager.urls(for: .moviesDirectory, in: .userDomainMask).first?.path ?? defaultDownloadPath
        case "mp3", "flac", "m4a", "wav":
            return fileManager.urls(for: .musicDirectory, in: .userDomainMask).first?.path ?? defaultDownloadPath
        case "pdf", "docx", "xlsx", "pptx", "txt":
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? defaultDownloadPath
        default:
            return defaultDownloadPath
        }
    }

    private func loadSettings() {
        let defaults = UserDefaults.standard
        if let path = defaults.string(forKey: MirrorSettings.StorageKeys.downloadDirectory), !path.isEmpty {
            self.defaultDownloadPath = path
        }
        if defaults.object(forKey: MirrorSettings.StorageKeys.autoOrganizeFiles) != nil {
            self.isAutoOrganizeEnabled = defaults.bool(forKey: MirrorSettings.StorageKeys.autoOrganizeFiles)
        }
    }
}
