//
//  NotificationViewController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

/// Notification view controller displaying Android notifications, with filtering, search,
/// and inline quick-reply capabilities.
public final class NotificationViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var connectionManager: ConnectionManager { ConnectionManager.shared }
    private var bridge: NotificationBridge { connectionManager.notificationBridge }

    private var filterPopUp: NSPopUpButton!
    private var searchField: NSSearchField!
    private var tableView: NSTableView!
    private var emptyLabel: NSTextField!

    private var selectedAppFilter: String = "All"
    private var searchQuery: String = ""
    private var displayedNotifications: [AndroidNotification] = []

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.view = root

        let header = createHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        tableView = NSTableView()
        tableView.headerView = nil
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NotificationColumn"))
        tableView.addTableColumn(col)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 90
        tableView.selectionHighlightStyle = .none
        scroll.documentView = tableView

        emptyLabel = NSTextField(labelWithString: "No Notifications")
        emptyLabel.font = .systemFont(ofSize: 16, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 52),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor)
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(notificationsUpdated(_:)),
            name: NotificationBridge.didUpdateNotificationsNotification,
            object: nil
        )

        reloadFilteredList()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func createHeaderView() -> NSView {
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(sep)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            sep.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1)
        ])

        searchField = NSSearchField()
        searchField.placeholderString = "Search notifications..."
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.widthAnchor.constraint(equalToConstant: 240).isActive = true
        stack.addArrangedSubview(searchField)

        filterPopUp = NSPopUpButton()
        filterPopUp.target = self
        filterPopUp.action = #selector(filterChanged(_:))
        stack.addArrangedSubview(filterPopUp)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        let clearBtn = NSButton(title: "Clear All", target: self, action: #selector(clearAllClicked(_:)))
        clearBtn.bezelStyle = .rounded
        stack.addArrangedSubview(clearBtn)

        return header
    }

    private func reloadFilteredList() {
        // Update popup items
        let apps = Array(Set(bridge.notifications.map { $0.appName })).sorted()
        let currentSelection = filterPopUp.titleOfSelectedItem ?? "All"
        filterPopUp.removeAllItems()
        filterPopUp.addItem(withTitle: "All")
        filterPopUp.addItems(withTitles: apps)
        if filterPopUp.itemTitles.contains(currentSelection) {
            filterPopUp.selectItem(withTitle: currentSelection)
        }

        displayedNotifications = bridge.notifications.filter { item in
            let matchesApp = (selectedAppFilter == "All") || (item.appName == selectedAppFilter)
            let matchesSearch = searchQuery.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchQuery) ||
                item.body.localizedCaseInsensitiveContains(searchQuery) ||
                item.appName.localizedCaseInsensitiveContains(searchQuery)
            return matchesApp && matchesSearch
        }

        emptyLabel.isHidden = !displayedNotifications.isEmpty
        tableView.reloadData()
    }

    @objc private func notificationsUpdated(_ notif: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.reloadFilteredList()
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        searchQuery = sender.stringValue
        reloadFilteredList()
    }

    @objc private func filterChanged(_ sender: NSPopUpButton) {
        selectedAppFilter = sender.titleOfSelectedItem ?? "All"
        reloadFilteredList()
    }

    @objc private func clearAllClicked(_ sender: NSButton) {
        bridge.clearAll()
        reloadFilteredList()
    }

    // MARK: - NSTableViewDataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return displayedNotifications.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < displayedNotifications.count else { return nil }
        let notification = displayedNotifications[row]

        let cellId = NSUserInterfaceItemIdentifier("NotificationCell")
        let cell: NotificationRowCell
        if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? NotificationRowCell {
            cell = reused
        } else {
            cell = NotificationRowCell()
            cell.identifier = cellId
        }

        cell.configure(with: notification) { [weak self] replyText in
            self?.bridge.sendReply(notificationId: notification.id, replyText: replyText)
        } onDismiss: { [weak self] in
            self?.bridge.dismissNotification(id: notification.id)
            self?.reloadFilteredList()
        }

        return cell
    }
}

// MARK: - Notification Row Cell

private final class NotificationRowCell: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(labelWithString: "")
    private let appNameLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let replyField = NSTextField()
    private let replyButton = NSButton(title: "Reply", target: nil, action: nil)
    private let dismissButton = NSButton(title: "Dismiss", target: nil, action: nil)

    private var onReply: ((String) -> Void)?
    private var onDismiss: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        appNameLabel.font = .systemFont(ofSize: 11, weight: .bold)
        appNameLabel.textColor = .droidAccent
        appNameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(appNameLabel)

        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        bodyLabel.font = .systemFont(ofSize: 12)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bodyLabel)

        replyField.placeholderString = "Quick reply..."
        replyField.font = .systemFont(ofSize: 12)
        replyField.target = self
        replyField.action = #selector(sendReply(_:))
        replyField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replyField)

        replyButton.bezelStyle = .rounded
        replyButton.target = self
        replyButton.action = #selector(sendReply(_:))
        replyButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replyButton)

        dismissButton.bezelStyle = .rounded
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked(_:))
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dismissButton)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        NSLayoutConstraint.activate([
            appNameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            appNameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),

            timeLabel.centerYAnchor.constraint(equalTo: appNameLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            titleLabel.topAnchor.constraint(equalTo: appNameLabel.bottomAnchor, constant: 3),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            bodyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            replyField.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 6),
            replyField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            replyField.widthAnchor.constraint(equalToConstant: 260),

            replyButton.centerYAnchor.constraint(equalTo: replyField.centerYAnchor),
            replyButton.leadingAnchor.constraint(equalTo: replyField.trailingAnchor, constant: 8),

            dismissButton.centerYAnchor.constraint(equalTo: replyField.centerYAnchor),
            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),

            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    func configure(with notification: AndroidNotification, onReply: @escaping (String) -> Void, onDismiss: @escaping () -> Void) {
        self.onReply = onReply
        self.onDismiss = onDismiss

        appNameLabel.stringValue = notification.appName.uppercased()
        titleLabel.stringValue = notification.title
        bodyLabel.stringValue = notification.body
        timeLabel.stringValue = notification.relativeTimeFormatted

        let canReply = notification.canReply
        replyField.isHidden = !canReply
        replyButton.isHidden = !canReply
    }

    @objc private func sendReply(_ sender: Any) {
        let text = replyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onReply?(text)
        replyField.stringValue = ""
    }

    @objc private func dismissClicked(_ sender: Any) {
        onDismiss?()
    }
}
