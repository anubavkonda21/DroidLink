//
//  FileTransferView.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import SwiftUI
import UniformTypeIdentifiers

/// File transfer view with drop zone, live progress tracking, and transfer history.
public struct FileTransferView: View {
    // MARK: - Environment & State

    @Environment(ConnectionManager.self) private var connectionManager
    @State private var isTargetedForDrop: Bool = false
    @State private var selectedTab: TransferTab = .active
    @State private var showingFilePicker: Bool = false

    public enum TransferTab: String, CaseIterable {
        case active = "Active Transfers"
        case history = "Transfer History"
    }

    public init() {}

    private var fileService: FileTransferService {
        connectionManager.fileTransferService
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Drop Zone Area
            dropZoneArea
                .padding(20)

            Divider()

            // Tab Selector & Controls
            HStack {
                Picker("Tabs", selection: $selectedTab) {
                    Text("Active (\(fileService.activeTransfers.count))").tag(TransferTab.active)
                    Text("History (\(fileService.transferHistory.count))").tag(TransferTab.history)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                Spacer()

                Button {
                    openFilePicker()
                } label: {
                    Label("Choose Files...", systemImage: "plus")
                }
                .buttonStyle(.bordered)

                if selectedTab == .history && !fileService.transferHistory.isEmpty {
                    Button(role: .destructive) {
                        fileService.clearHistory()
                    } label: {
                        Text("Clear History")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // List Content
            if selectedTab == .active {
                if fileService.activeTransfers.isEmpty {
                    emptyActiveState
                } else {
                    activeTransfersList
                }
            } else {
                if fileService.transferHistory.isEmpty {
                    emptyHistoryState
                } else {
                    historyTransfersList
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Drop Zone Area

    private var dropZoneArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    isTargetedForDrop ? Color.blue : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [8])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargetedForDrop ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor))
                )

            VStack(spacing: 12) {
                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(isTargetedForDrop ? .blue : .secondary)

                VStack(spacing: 4) {
                    Text("Drop Files to Transfer to Android")
                        .font(.headline)

                    Text("Files will be saved into /sdcard/Download or auto-organized")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(28)
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargetedForDrop) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Active Transfers List

    private var activeTransfersList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(fileService.activeTransfers) { item in
                    activeTransferRow(item: item)
                }
            }
            .padding(20)
        }
    }

    private func activeTransferRow(item: FileTransferItem) -> some View {
        HStack(spacing: 16) {
            // File Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: item.systemIconName)
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(item.fileName)
                        .font(.subheadline.bold())
                        .lineLimit(1)

                    Spacer()

                    Text(item.formattedSpeed)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }

                // Progress Bar
                ProgressView(value: item.progress)
                    .tint(.blue)

                HStack {
                    Text("\(item.formattedBytesTransferred) of \(item.formattedFileSize)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(item.formattedEta)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            // Cancel Button
            Button {
                fileService.cancelTransfer(id: item.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - History List

    private var historyTransfersList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(fileService.transferHistory) { item in
                    historyTransferRow(item: item)
                }
            }
            .padding(20)
        }
    }

    private func historyTransferRow(item: FileTransferItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: item.status == .completed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(item.status == .completed ? .green : .red)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.fileName)
                    .font(.subheadline.bold())
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(item.formattedFileSize)
                    Text("•")
                    Text(item.direction.rawValue)
                    if let err = item.errorMessage {
                        Text("•")
                        Text(err).foregroundStyle(.red)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if let path = item.localPath, FileManager.default.fileExists(atPath: path) {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Empty States

    private var emptyActiveState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No Active Transfers")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var emptyHistoryState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No Transfer History")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - File Selection Dialog

    private func openFilePicker() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = true
        openPanel.begin { result in
            if result == .OK {
                fileService.sendFiles(urls: openPanel.urls)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didHandle = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        if let url = item as? URL {
                            fileService.sendFile(url: url)
                        }
                        return
                    }
                    fileService.sendFile(url: url)
                }
                didHandle = true
            }
        }
        return didHandle
    }
}
