//
//  FileTransferViewController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit
import UniformTypeIdentifiers

/// File transfer view controller with drop zone, live progress tracking, and transfer history.
public final class FileTransferViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var connectionManager: ConnectionManager { ConnectionManager.shared }
    private var fileService: FileTransferService { connectionManager.fileTransferService }

    private var dropZone: DropZoneView!
    private var tabSegment: NSSegmentedControl!
    private var clearHistoryBtn: NSButton!
    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!

    private var selectedTab: Int = 0 // 0: Active, 1: History

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.view = root

        // Drop zone at top
        dropZone = DropZoneView()
        dropZone.translatesAutoresizingMaskIntoConstraints = false
        dropZone.onFilesDropped = { [weak self] urls in
            self?.fileService.sendFiles(urls: urls)
        }
        dropZone.onChooseFiles = { [weak self] in
            self?.openFilePicker()
        }
        root.addSubview(dropZone)

        // Middle controls bar
        let controlsBar = createControlsBar()
        controlsBar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controlsBar)

        // Table view in scroll view
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        tableView = NSTableView()
        tableView.headerView = nil
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TransferCol"))
        tableView.addTableColumn(col)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.selectionHighlightStyle = .none
        scroll.documentView = tableView

        emptyLabel = NSTextField(labelWithString: "No Active Transfers")
        emptyLabel.font = .systemFont(ofSize: 15, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            dropZone.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            dropZone.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            dropZone.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            dropZone.heightAnchor.constraint(equalToConstant: 120),

            controlsBar.topAnchor.constraint(equalTo: dropZone.bottomAnchor, constant: 14),
            controlsBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            controlsBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            controlsBar.heightAnchor.constraint(equalToConstant: 44),

            scroll.topAnchor.constraint(equalTo: controlsBar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(transfersUpdated(_:)),
            name: FileTransferService.didUpdateTransfersNotification,
            object: nil
        )

        updateList()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func createControlsBar() -> NSView {
        let bar = NSView()
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(sep)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            stack.centerYAnchor.constraint(equalTo: bar.centerYAnchor),

            sep.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1)
        ])

        tabSegment = NSSegmentedControl(labels: ["Active (0)", "History (0)"], trackingMode: .selectOne, target: self, action: #selector(tabChanged(_:)))
        tabSegment.selectedSegment = 0
        stack.addArrangedSubview(tabSegment)

        let chooseBtn = NSButton(title: "Choose Files...", target: self, action: #selector(chooseFilesClicked(_:)))
        chooseBtn.bezelStyle = .rounded
        stack.addArrangedSubview(chooseBtn)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        clearHistoryBtn = NSButton(title: "Clear History", target: self, action: #selector(clearHistoryClicked(_:)))
        clearHistoryBtn.bezelStyle = .rounded
        clearHistoryBtn.isHidden = true
        stack.addArrangedSubview(clearHistoryBtn)

        return bar
    }

    private func updateList() {
        tabSegment.setLabel("Active (\(fileService.activeTransfers.count))", forSegment: 0)
        tabSegment.setLabel("History (\(fileService.transferHistory.count))", forSegment: 1)

        let items = selectedTab == 0 ? fileService.activeTransfers : fileService.transferHistory
        emptyLabel.stringValue = selectedTab == 0 ? "No Active Transfers" : "No Transfer History"
        emptyLabel.isHidden = !items.isEmpty
        clearHistoryBtn.isHidden = (selectedTab == 0 || fileService.transferHistory.isEmpty)

        tableView.reloadData()
    }

    @objc private func transfersUpdated(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.updateList()
        }
    }

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        selectedTab = sender.selectedSegment
        updateList()
    }

    @objc private func chooseFilesClicked(_ sender: NSButton) {
        openFilePicker()
    }

    @objc private func clearHistoryClicked(_ sender: NSButton) {
        fileService.clearHistory()
        updateList()
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            fileService.sendFiles(urls: panel.urls)
        }
    }

    // MARK: - NSTableViewDataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return selectedTab == 0 ? fileService.activeTransfers.count : fileService.transferHistory.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let items = selectedTab == 0 ? fileService.activeTransfers : fileService.transferHistory
        guard row < items.count else { return nil }
        let item = items[row]

        let cellId = NSUserInterfaceItemIdentifier("TransferCell")
        let cell: FileTransferRowCell
        if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? FileTransferRowCell {
            cell = reused
        } else {
            cell = FileTransferRowCell()
            cell.identifier = cellId
        }

        cell.configure(with: item) { [weak self] in
            if item.status == .transferring || item.status == .queued {
                self?.fileService.cancelTransfer(id: item.id)
            }
        }

        return cell
    }
}

// MARK: - Drop Zone View

private final class DropZoneView: NSView {
    var onFilesDropped: (([URL]) -> Void)?
    var onChooseFiles: (() -> Void)?

    private var isHighlighted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.separatorColor.cgColor
        registerForDraggedTypes([.fileURL])

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        let icon = NSImageView(image: NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .droidAccent
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        stack.addArrangedSubview(icon)

        let label = NSTextField(labelWithString: "Drag and drop files here to send to phone")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        stack.addArrangedSubview(label)

        let btn = NSButton(title: "Browse Files", target: self, action: #selector(browseClicked(_:)))
        btn.bezelStyle = .rounded
        stack.addArrangedSubview(btn)
    }

    @objc private func browseClicked(_ sender: NSButton) {
        onChooseFiles?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        layer?.borderColor = NSColor.droidAccent.cgColor
        layer?.backgroundColor = NSColor.droidAccent.withAlphaComponent(0.1).cgColor
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.clear.cgColor

        guard let items = sender.draggingPasteboard.pasteboardItems else { return false }
        var urls: [URL] = []
        for item in items {
            if let string = item.string(forType: .fileURL), let url = URL(string: string) {
                urls.append(url)
            }
        }
        if !urls.isEmpty {
            onFilesDropped?(urls)
            return true
        }
        return false
    }
}

// MARK: - File Transfer Row Cell

private final class FileTransferRowCell: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailsLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let actionButton = NSButton(title: "Cancel", target: nil, action: nil)

    private var onAction: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.image = NSImage(systemSymbolName: "doc.fill", accessibilityDescription: nil)
        iconView.contentTintColor = .droidAccent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        detailsLabel.font = .systemFont(ofSize: 11)
        detailsLabel.textColor = .secondaryLabelColor
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(detailsLabel)

        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1.0
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressBar)

        actionButton.bezelStyle = .rounded
        actionButton.target = self
        actionButton.action = #selector(buttonAction(_:))
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(actionButton)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 28),
            iconView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -12),

            progressBar.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            progressBar.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            progressBar.widthAnchor.constraint(equalToConstant: 200),
            progressBar.heightAnchor.constraint(equalToConstant: 6),

            detailsLabel.centerYAnchor.constraint(equalTo: progressBar.centerYAnchor),
            detailsLabel.leadingAnchor.constraint(equalTo: progressBar.trailingAnchor, constant: 10),

            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            actionButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    func configure(with item: FileTransferItem, onAction: @escaping () -> Void) {
        self.onAction = onAction

        nameLabel.stringValue = item.fileName
        progressBar.doubleValue = item.progress

        switch item.status {
        case .queued, .paused:
            detailsLabel.stringValue = "\(item.formattedFileSize) • Queued..."
            actionButton.title = "Cancel"
            actionButton.isHidden = false
        case .transferring:
            detailsLabel.stringValue = "\(item.formattedFileSize) • \(item.formattedSpeed) • \(Int(item.progress * 100))%"
            actionButton.title = "Cancel"
            actionButton.isHidden = false
        case .completed:
            detailsLabel.stringValue = "\(item.formattedFileSize) • Completed"
            actionButton.isHidden = true
        case .failed:
            detailsLabel.stringValue = "\(item.formattedFileSize) • Failed"
            actionButton.title = "Retry"
            actionButton.isHidden = false
        case .cancelled:
            detailsLabel.stringValue = "\(item.formattedFileSize) • Cancelled"
            actionButton.isHidden = true
        }
    }

    @objc private func buttonAction(_ sender: NSButton) {
        onAction?()
    }
}
