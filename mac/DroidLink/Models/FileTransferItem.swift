//
//  FileTransferItem.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import Foundation

/// Represents a single file transfer between macOS and the Android device.
public struct FileTransferItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    // MARK: - Transfer Direction & Status

    public enum Direction: String, Codable, CaseIterable, Sendable {
        case toAndroid = "To Android"
        case toMac = "To Mac"

        public var iconName: String {
            switch self {
            case .toAndroid:
                return "arrow.up.circle.fill"
            case .toMac:
                return "arrow.down.circle.fill"
            }
        }
    }

    public enum Status: String, Codable, CaseIterable, Sendable {
        case queued = "Queued"
        case transferring = "Transferring"
        case paused = "Paused"
        case completed = "Completed"
        case failed = "Failed"
        case cancelled = "Cancelled"

        public var isTerminal: Bool {
            switch self {
            case .completed, .failed, .cancelled:
                return true
            case .queued, .transferring, .paused:
                return false
            }
        }
    }

    // MARK: - Properties

    public var id: UUID
    public var fileName: String
    public var fileSize: Int64
    public var bytesTransferred: Int64
    public var progress: Double // 0.0 to 1.0
    public var speed: Double    // Bytes per second
    public var direction: Direction
    public var status: Status
    public var localPath: String?
    public var remotePath: String?
    public var errorMessage: String?
    public var startDate: Date?
    public var completionDate: Date?

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        fileName: String,
        fileSize: Int64,
        bytesTransferred: Int64 = 0,
        progress: Double = 0.0,
        speed: Double = 0.0,
        direction: Direction,
        status: Status = .queued,
        localPath: String? = nil,
        remotePath: String? = nil,
        errorMessage: String? = nil,
        startDate: Date? = nil,
        completionDate: Date? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.fileSize = fileSize
        self.bytesTransferred = bytesTransferred
        self.progress = progress
        self.speed = speed
        self.direction = direction
        self.status = status
        self.localPath = localPath
        self.remotePath = remotePath
        self.errorMessage = errorMessage
        self.startDate = startDate
        self.completionDate = completionDate
    }

    // MARK: - Computed Properties

    public var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public var formattedBytesTransferred: String {
        ByteCountFormatter.string(fromByteCount: bytesTransferred, countStyle: .file)
    }

    public var formattedSpeed: String {
        guard status == .transferring, speed > 0 else { return "-- KB/s" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return "\(formatter.string(fromByteCount: Int64(speed)))/s"
    }

    public var formattedProgressPercentage: String {
        let percent = Int(progress * 100)
        return "\(percent)%"
    }

    public var formattedEta: String {
        guard status == .transferring, speed > 1024 else { return "" }
        let remainingBytes = max(0, fileSize - bytesTransferred)
        let remainingSeconds = Double(remainingBytes) / speed
        if remainingSeconds < 60 {
            return "\(Int(remainingSeconds))s remaining"
        } else {
            let minutes = Int(remainingSeconds / 60)
            let seconds = Int(remainingSeconds) % 60
            return "\(minutes)m \(seconds)s remaining"
        }
    }

    public var fileExtension: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    public var systemIconName: String {
        switch fileExtension {
        case "jpg", "jpeg", "png", "heic", "webp", "gif":
            return "photo.fill"
        case "mp4", "mkv", "mov", "avi":
            return "film.fill"
        case "mp3", "flac", "m4a", "wav", "aac":
            return "music.note"
        case "pdf":
            return "doc.text.fill"
        case "zip", "tar", "gz", "7z", "rar":
            return "archivebox.fill"
        case "apk":
            return "shippingbox.fill"
        default:
            return "doc.fill"
        }
    }

    // MARK: - Previews & Mocks

    public static let mockActiveTransfers: [FileTransferItem] = [
        FileTransferItem(
            fileName: "Android_Setup_2026.apk",
            fileSize: 48_500_000,
            bytesTransferred: 32_100_000,
            progress: 0.66,
            speed: 12_400_000,
            direction: .toAndroid,
            status: .transferring,
            remotePath: "/sdcard/Download/Android_Setup_2026.apk"
        ),
        FileTransferItem(
            fileName: "Holiday_Photos.zip",
            fileSize: 1_250_000_000,
            bytesTransferred: 250_000_000,
            progress: 0.20,
            speed: 24_500_000,
            direction: .toMac,
            status: .transferring,
            localPath: "/Users/user/Downloads/Holiday_Photos.zip"
        )
    ]

    public static let mockCompletedTransfers: [FileTransferItem] = [
        FileTransferItem(
            fileName: "Presentation_Final.pdf",
            fileSize: 12_800_000,
            bytesTransferred: 12_800_000,
            progress: 1.0,
            speed: 0,
            direction: .toAndroid,
            status: .completed,
            completionDate: Date().addingTimeInterval(-1800)
        ),
        FileTransferItem(
            fileName: "Screenshot_20261103_093021.png",
            fileSize: 2_450_000,
            bytesTransferred: 2_450_000,
            progress: 1.0,
            speed: 0,
            direction: .toMac,
            status: .completed,
            completionDate: Date().addingTimeInterval(-4200)
        )
    ]
}
