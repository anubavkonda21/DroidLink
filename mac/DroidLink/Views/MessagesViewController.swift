//
//  MessagesViewController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//
//  Apple Messages-style page for the phone's SMS: conversation list on the left (fixed width),
//  chat bubbles and a compose bar on the right. Data comes from SMSStore.
//

import AppKit

public final class MessagesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
    private var store: SMSStore { SMSStore.shared }
    private var selectedNumber: String?
    private var searchQuery = ""

    // left
    private var searchField: NSSearchField!
    private var conversationsTableView: NSTableView!
    private var listStatusView: StatusOverlay!
    private var archivedButton: NSButton!
    private var selectingInCode = false   // true while reloadAll restores the selection

    // right
    private var headerAvatar: AvatarView!
    private var headerNameLabel: NSTextField!
    private var headerNumberLabel: NSTextField!
    private var threadScroll: NSScrollView!
    private var threadStack: NSStackView!
    private var threadPlaceholder: NSTextField!
    private var composeField: NSTextField!
    private var sendButton: NSButton!
    private var composeBar: NSView!
    private var header: NSView!
    private var lastThreadWidth: CGFloat = 0

    private var filteredConversations: [Conversation] {
        let all = store.visibleConversations
        guard !searchQuery.isEmpty else { return all }
        return all.filter {
            $0.contactName.localizedCaseInsensitiveContains(searchQuery) ||
            $0.contactNumber.contains(searchQuery) ||
            $0.messages.contains { $0.body.localizedCaseInsensitiveContains(searchQuery) }
        }
    }

    private var selectedConversation: Conversation? {
        guard let n = selectedNumber else { return nil }
        return store.conversations.first { $0.contactNumber == n }
    }

    // MARK: - Lifecycle

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        view = root

        let left = makeListPane()
        let right = makeThreadPane()
        let divider = NSBox()
        divider.boxType = .separator
        [left, divider, right].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; root.addSubview($0) }

        NSLayoutConstraint.activate([
            left.topAnchor.constraint(equalTo: root.topAnchor),
            left.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            left.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            left.widthAnchor.constraint(equalToConstant: 300),

            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: left.trailingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            right.topAnchor.constraint(equalTo: root.topAnchor),
            right.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            right.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            right.trailingAnchor.constraint(equalTo: root.trailingAnchor)
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(storeChanged), name: SMSStore.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(connectionChanged), name: ConnectionManager.didChangeStatusNotification, object: nil)
        reloadAll()
    }

    public override func viewWillAppear() {
        super.viewWillAppear()
        store.refresh()
        reloadAll()
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        let w = threadScroll.contentView.bounds.width
        if abs(w - lastThreadWidth) > 20 { // bubble widths depend on the pane width
            lastThreadWidth = w
            rebuildThread(scrollToEnd: false)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func storeChanged() {
        reloadAll()
    }

    @objc private func connectionChanged() {
        DispatchQueue.main.async {
            if ConnectionManager.shared.status.isConnectedOrMirroring, self.view.window != nil { self.store.refresh() }
            self.reloadAll()
        }
    }

    // MARK: - Left pane

    private func makeListPane() -> NSView {
        let pane = NSView()

        searchField = NSSearchField()
        searchField.placeholderString = "Search"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.sendsSearchStringImmediately = true
        searchField.controlSize = .large
        searchField.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(searchField)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(scroll)

        conversationsTableView = NSTableView()
        conversationsTableView.headerView = nil
        conversationsTableView.style = .inset
        conversationsTableView.backgroundColor = .clear
        conversationsTableView.intercellSpacing = NSSize(width: 0, height: 2)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ConversationCol"))
        col.resizingMask = .autoresizingMask
        conversationsTableView.addTableColumn(col)
        conversationsTableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        conversationsTableView.dataSource = self
        conversationsTableView.delegate = self
        conversationsTableView.rowHeight = 64
        conversationsTableView.target = self
        conversationsTableView.action = #selector(rowClicked(_:)) // clicking the already-open chat still marks it read
        let rowMenu = NSMenu()
        rowMenu.delegate = self
        conversationsTableView.menu = rowMenu
        scroll.documentView = conversationsTableView

        archivedButton = NSButton(title: "", target: self, action: #selector(toggleArchivedView(_:)))
        archivedButton.isBordered = false
        archivedButton.font = .systemFont(ofSize: 12, weight: .medium)
        archivedButton.contentTintColor = .secondaryLabelColor
        archivedButton.imagePosition = .imageLeading
        archivedButton.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(archivedButton)

        listStatusView = StatusOverlay()
        listStatusView.translatesAutoresizingMaskIntoConstraints = false
        listStatusView.onButton = { [weak self] in self?.store.refresh() }
        pane.addSubview(listStatusView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: pane.topAnchor, constant: 14),
            searchField.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -14),

            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: archivedButton.topAnchor, constant: -4),

            archivedButton.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 18),
            archivedButton.bottomAnchor.constraint(equalTo: pane.bottomAnchor, constant: -10),

            listStatusView.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            listStatusView.centerYAnchor.constraint(equalTo: pane.centerYAnchor),
            listStatusView.widthAnchor.constraint(equalTo: pane.widthAnchor, constant: -48)
        ])
        return pane
    }

    // MARK: - Right pane

    private func makeThreadPane() -> NSView {
        let pane = NSView()
        pane.wantsLayer = true
        pane.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

        // header: "To:" style, name centred like Messages
        header = NSView()
        header.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(header)

        headerAvatar = AvatarView(size: 28)
        headerNameLabel = NSTextField(labelWithString: "")
        headerNameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerNameLabel.lineBreakMode = .byTruncatingTail
        headerNumberLabel = NSTextField(labelWithString: "")
        headerNumberLabel.font = .systemFont(ofSize: 11)
        headerNumberLabel.textColor = .secondaryLabelColor

        let names = NSStackView(views: [headerNameLabel, headerNumberLabel])
        names.orientation = .vertical
        names.alignment = .leading
        names.spacing = 0
        let headerStack = NSStackView(views: [headerAvatar, names])
        headerStack.orientation = .horizontal
        headerStack.spacing = 10
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerStack)

        let headerSep = NSBox()
        headerSep.boxType = .separator
        headerSep.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(headerSep)

        // thread
        threadScroll = NSScrollView()
        threadScroll.hasVerticalScroller = true
        threadScroll.borderType = .noBorder
        threadScroll.drawsBackground = false
        threadScroll.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(threadScroll)

        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        threadScroll.documentView = doc

        threadStack = NSStackView()
        threadStack.orientation = .vertical
        threadStack.alignment = .leading
        threadStack.spacing = 4
        threadStack.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(threadStack)

        threadPlaceholder = NSTextField(labelWithString: "")
        threadPlaceholder.font = .systemFont(ofSize: 15, weight: .medium)
        threadPlaceholder.textColor = .tertiaryLabelColor
        threadPlaceholder.alignment = .center
        threadPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(threadPlaceholder)

        // compose bar
        composeBar = NSView()
        composeBar.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(composeBar)

        let capsule = NSView()
        capsule.wantsLayer = true
        capsule.layer?.cornerRadius = 16
        capsule.layer?.borderWidth = 1
        capsule.layer?.borderColor = NSColor.separatorColor.cgColor
        capsule.translatesAutoresizingMaskIntoConstraints = false
        composeBar.addSubview(capsule)

        composeField = NSTextField()
        composeField.placeholderString = "Text Message"
        composeField.isBordered = false
        composeField.drawsBackground = false
        composeField.focusRingType = .none
        composeField.font = .systemFont(ofSize: 13)
        composeField.usesSingleLineMode = false
        composeField.cell?.wraps = true
        composeField.cell?.isScrollable = false
        composeField.maximumNumberOfLines = 5
        composeField.delegate = self
        composeField.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(composeField)

        sendButton = NSButton(image: NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")!,
                              target: self, action: #selector(sendClicked(_:)))
        sendButton.isBordered = false
        sendButton.imageScaling = .scaleProportionallyUpOrDown
        sendButton.contentTintColor = .droidAccent
        sendButton.symbolConfiguration = .init(pointSize: 22, weight: .regular)
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(sendButton)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: pane.topAnchor),
            header.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 56),
            headerStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            headerStack.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -20),
            headerSep.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerSep.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerSep.bottomAnchor.constraint(equalTo: header.bottomAnchor),

            threadScroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            threadScroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            threadScroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            threadScroll.bottomAnchor.constraint(equalTo: composeBar.topAnchor),

            doc.topAnchor.constraint(equalTo: threadScroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: threadScroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: threadScroll.contentView.trailingAnchor),
            threadStack.topAnchor.constraint(equalTo: doc.topAnchor, constant: 16),
            threadStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            threadStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            threadStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor, constant: -16),

            threadPlaceholder.centerXAnchor.constraint(equalTo: pane.centerXAnchor),
            threadPlaceholder.centerYAnchor.constraint(equalTo: pane.centerYAnchor),

            composeBar.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            composeBar.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            composeBar.bottomAnchor.constraint(equalTo: pane.bottomAnchor),

            capsule.topAnchor.constraint(equalTo: composeBar.topAnchor, constant: 10),
            capsule.bottomAnchor.constraint(equalTo: composeBar.bottomAnchor, constant: -14),
            capsule.leadingAnchor.constraint(equalTo: composeBar.leadingAnchor, constant: 20),
            capsule.trailingAnchor.constraint(equalTo: composeBar.trailingAnchor, constant: -20),
            capsule.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),

            composeField.leadingAnchor.constraint(equalTo: capsule.leadingAnchor, constant: 14),
            composeField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -6),
            composeField.topAnchor.constraint(equalTo: capsule.topAnchor, constant: 7),
            composeField.bottomAnchor.constraint(equalTo: capsule.bottomAnchor, constant: -7),

            sendButton.trailingAnchor.constraint(equalTo: capsule.trailingAnchor, constant: -4),
            sendButton.bottomAnchor.constraint(equalTo: capsule.bottomAnchor, constant: -4),
            sendButton.widthAnchor.constraint(equalToConstant: 24),
            sendButton.heightAnchor.constraint(equalToConstant: 24)
        ])
        return pane
    }

    // MARK: - Reload

    private func reloadAll() {
        guard isViewLoaded else { return }
        if selectedNumber == nil || selectedConversation == nil {
            selectedNumber = filteredConversations.first?.contactNumber
        }
        selectingInCode = true
        conversationsTableView.reloadData()
        if let n = selectedNumber, let row = filteredConversations.firstIndex(where: { $0.contactNumber == n }) {
            conversationsTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        selectingInCode = false
        updateListStatus()
        updateArchivedButton()
        rebuildThread(scrollToEnd: true)
        // a new text in the chat you're looking at counts as read (unless you marked it unread yourself)
        if let conv = selectedConversation, view.window?.isKeyWindow == true, userOpenedChat,
           store.isUnread(conv), !store.isManuallyUnread(conv) {
            DispatchQueue.main.async { self.store.markRead(conv) }
        }
    }

    private var userOpenedChat = false

    private func updateArchivedButton() {
        let n = store.archivedCount
        archivedButton.isHidden = n == 0 && !store.showingArchived
        if store.showingArchived {
            archivedButton.title = "Back to Messages"
            archivedButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil)
        } else {
            archivedButton.title = "Archived (\(n))"
            archivedButton.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: nil)
        }
    }

    private func updateListStatus() {
        let connected = ConnectionManager.shared.status.isConnectedOrMirroring
        if !connected && store.conversations.isEmpty {
            listStatusView.show(symbol: "iphone.slash", title: "Phone not connected",
                                detail: "Connect your phone to see its messages.", button: nil)
        } else if store.state == .permissionMissing {
            listStatusView.show(symbol: "lock.shield", title: "Allow SMS access",
                                detail: "On your phone, open DroidLink and allow SMS, or go to Settings › Apps › DroidLink › Permissions › SMS.",
                                button: "Try Again")
        } else if store.state == .loading && store.conversations.isEmpty {
            listStatusView.show(symbol: nil, title: "Loading conversations…", detail: nil, button: nil, spinning: true)
        } else if store.conversations.isEmpty {
            listStatusView.show(symbol: "message", title: "No Messages",
                                detail: store.state == .idle ? "Update DroidLink on your phone to sync texts." : nil,
                                button: "Refresh")
        } else if filteredConversations.isEmpty && store.showingArchived {
            listStatusView.show(symbol: "archivebox", title: "No Archived Chats", detail: nil, button: nil)
        } else if filteredConversations.isEmpty && searchQuery.isEmpty {
            listStatusView.show(symbol: "message", title: "No Messages",
                                detail: "Archived chats are under Archived below.", button: nil)
        } else if filteredConversations.isEmpty {
            listStatusView.show(symbol: nil, title: "No Results", detail: nil, button: nil)
        } else {
            listStatusView.isHidden = true
        }
    }

    private func rebuildThread(scrollToEnd: Bool) {
        threadStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let conv = selectedConversation else {
            header.isHidden = true
            composeBar.isHidden = true
            threadPlaceholder.isHidden = store.conversations.isEmpty
            threadPlaceholder.stringValue = "Select a conversation"
            return
        }
        header.isHidden = false
        composeBar.isHidden = false
        threadPlaceholder.isHidden = true
        headerAvatar.configure(name: conv.contactName, isNumberOnly: conv.contactName == conv.contactNumber)
        headerNameLabel.stringValue = conv.contactName
        headerNumberLabel.stringValue = conv.contactName == conv.contactNumber ? "Text Message" : conv.contactNumber
        headerNumberLabel.isHidden = false
        composeField.isEnabled = store.canSend
        composeField.placeholderString = store.canSend ? "Text Message" : "Allow SMS sending on your phone to reply"
        updateSendButton()

        let width = max(320, threadScroll.contentView.bounds.width)
        let maxBubble = min(520, width * 0.66)
        let messages = conv.messages.sorted { $0.timestamp < $1.timestamp }
        var previous: Message?
        for msg in messages {
            if previous == nil || msg.timestamp.timeIntervalSince(previous!.timestamp) > 3600 {
                addArranged(DateSeparator(date: msg.timestamp), topGap: previous == nil ? 0 : 12)
            }
            let sameSide = previous != nil && previous!.isIncoming == msg.isIncoming
            addArranged(BubbleRow(message: msg, maxWidth: maxBubble), topGap: sameSide ? 0 : 6)
            previous = msg
        }
        if let last = messages.last, !last.isIncoming {
            let caption: String
            switch last.deliveryStatus {
            case .failed: caption = "Not Delivered"
            case .pending: caption = "Sending…"
            default: caption = "Sent"
            }
            addArranged(StatusCaption(text: caption, failed: last.deliveryStatus == .failed), topGap: 0)
        }

        if scrollToEnd {
            view.layoutSubtreeIfNeeded()
            let doc = threadScroll.documentView!
            let y = max(0, doc.bounds.height - threadScroll.contentView.bounds.height)
            threadScroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            threadScroll.reflectScrolledClipView(threadScroll.contentView)
        }
    }

    private func addArranged(_ v: NSView, topGap: CGFloat) {
        if topGap > 0, let last = threadStack.arrangedSubviews.last {
            threadStack.setCustomSpacing(threadStack.spacing + topGap, after: last)
        }
        threadStack.addArrangedSubview(v)
        v.widthAnchor.constraint(equalTo: threadStack.widthAnchor).isActive = true
    }

    // MARK: - Actions

    @objc private func searchChanged(_ sender: NSSearchField) {
        searchQuery = sender.stringValue
        conversationsTableView.reloadData()
        if let n = selectedNumber, let row = filteredConversations.firstIndex(where: { $0.contactNumber == n }) {
            conversationsTableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        updateListStatus()
    }

    @objc private func sendClicked(_ sender: Any?) {
        let text = composeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let conv = selectedConversation, store.canSend else { return }
        composeField.stringValue = ""
        updateSendButton()
        store.send(text, to: conv)
    }

    private func updateSendButton() {
        let hasText = !composeField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText && store.canSend
        sendButton.contentTintColor = sendButton.isEnabled ? .droidAccent : .tertiaryLabelColor
    }

    public func controlTextDidChange(_ obj: Notification) {
        updateSendButton()
    }

    /// Return sends, Option-Return adds a new line (like Messages).
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                sendClicked(nil)
            }
            return true
        }
        return false
    }

    // MARK: - Table

    public func numberOfRows(in tableView: NSTableView) -> Int {
        filteredConversations.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let list = filteredConversations
        guard row < list.count else { return nil }
        let id = NSUserInterfaceItemIdentifier("ConversationCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? ConversationRowCell) ?? {
            let c = ConversationRowCell(); c.identifier = id; return c
        }()
        cell.configure(with: list[row])
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard !selectingInCode else { return }
        let row = conversationsTableView.selectedRow
        let list = filteredConversations
        guard row >= 0, row < list.count else { return }
        open(list[row])
    }

    @objc private func rowClicked(_ sender: Any?) {
        let row = conversationsTableView.clickedRow
        let list = filteredConversations
        guard row >= 0, row < list.count else { return }
        open(list[row])
    }

    /// The user opened a chat (click or arrow keys): show it and clear its blue dot.
    private func open(_ conv: Conversation) {
        userOpenedChat = true
        if conv.contactNumber != selectedNumber {
            selectedNumber = conv.contactNumber
            rebuildThread(scrollToEnd: true)
            view.window?.makeFirstResponder(composeField)
        }
        if store.isUnread(conv) { store.markRead(conv) }
    }

    // MARK: - Swipe actions (like Messages: swipe right = Unread / Pin, swipe left = Archive / More)

    public func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        let list = filteredConversations
        guard row < list.count else { return [] }
        let conv = list[row]

        if edge == .leading {
            let unread = store.isUnread(conv)
            let readAction = NSTableViewRowAction(style: .regular, title: unread ? "Read" : "Unread") { [weak self] _, _ in
                guard let self else { return }
                unread ? self.store.markRead(conv) : self.store.markUnread(conv)
                tableView.rowActionsVisible = false
            }
            readAction.backgroundColor = .droidAccent
            readAction.image = NSImage(systemSymbolName: unread ? "message" : "message.badge", accessibilityDescription: nil)

            let pinned = store.isPinned(conv)
            let pinAction = NSTableViewRowAction(style: .regular, title: pinned ? "Unpin" : "Pin") { [weak self] _, _ in
                self?.store.togglePin(conv)
                tableView.rowActionsVisible = false
            }
            pinAction.backgroundColor = .systemOrange
            pinAction.image = NSImage(systemSymbolName: pinned ? "pin.slash.fill" : "pin.fill", accessibilityDescription: nil)
            return [readAction, pinAction]
        }

        let archived = store.isArchived(conv)
        let archiveAction = NSTableViewRowAction(style: .regular, title: archived ? "Unarchive" : "Archive") { [weak self] _, _ in
            self?.store.toggleArchive(conv)
            tableView.rowActionsVisible = false
        }
        archiveAction.backgroundColor = .systemTeal
        archiveAction.image = NSImage(systemSymbolName: archived ? "tray.and.arrow.up.fill" : "archivebox.fill", accessibilityDescription: nil)

        let moreAction = NSTableViewRowAction(style: .regular, title: "More") { [weak self] _, row in
            guard let self else { return }
            let menu = NSMenu()
            self.fillMenu(menu, for: conv)
            let rect = tableView.rect(ofRow: row)
            menu.popUp(positioning: nil, at: NSPoint(x: rect.maxX - 80, y: rect.maxY), in: tableView)
            tableView.rowActionsVisible = false
        }
        moreAction.backgroundColor = .systemGray
        moreAction.image = NSImage(systemSymbolName: "ellipsis.circle.fill", accessibilityDescription: nil)
        return [archiveAction, moreAction]
    }

    // MARK: - Right-click / More menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = conversationsTableView.clickedRow
        let list = filteredConversations
        guard row >= 0, row < list.count else { return }
        fillMenu(menu, for: list[row])
    }

    private func fillMenu(_ menu: NSMenu, for conv: Conversation) {
        func item(_ title: String, _ symbol: String, _ action: @escaping () -> Void) {
            let mi = NSMenuItem(title: title, action: #selector(runMenuBlock(_:)), keyEquivalent: "")
            mi.target = self
            mi.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            mi.representedObject = MenuBlock(action)
            menu.addItem(mi)
        }
        if store.isUnread(conv) {
            item("Mark as Read", "message") { [weak self] in self?.store.markRead(conv) }
        } else {
            item("Mark as Unread", "message.badge") { [weak self] in self?.store.markUnread(conv) }
        }
        if store.isPinned(conv) {
            item("Unpin", "pin.slash") { [weak self] in self?.store.togglePin(conv) }
        } else if !store.isArchived(conv) {
            item("Pin", "pin") { [weak self] in self?.store.togglePin(conv) }
        }
        if store.isArchived(conv) {
            item("Unarchive", "tray.and.arrow.up") { [weak self] in self?.store.toggleArchive(conv) }
        } else {
            item("Archive", "archivebox") { [weak self] in self?.store.toggleArchive(conv) }
        }
        menu.addItem(.separator())
        item("Copy Phone Number", "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(conv.contactNumber, forType: .string)
        }
    }

    @objc private func runMenuBlock(_ sender: NSMenuItem) {
        (sender.representedObject as? MenuBlock)?.action()
    }

    @objc private func toggleArchivedView(_ sender: Any?) {
        selectedNumber = nil
        userOpenedChat = false
        store.showingArchived.toggle()
    }
}

private final class MenuBlock {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
}

// MARK: - Pieces

/// Round avatar with initials on a grey gradient, like Contacts without a photo.
private final class AvatarView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let gradient = CAGradientLayer()
    private let side: CGFloat

    init(size: CGFloat) {
        side = size
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        wantsLayer = true
        layer?.cornerRadius = size / 2
        layer?.masksToBounds = true
        gradient.colors = [NSColor(white: 0.66, alpha: 1).cgColor, NSColor(white: 0.52, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        layer?.addSublayer(gradient)

        label.font = .systemFont(ofSize: size * 0.4, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        icon.image = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: size * 0.5, weight: .regular)
        icon.contentTintColor = .white
        [label, icon].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
            $0.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            $0.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
        }
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        gradient.frame = bounds
    }

    func configure(name: String, isNumberOnly: Bool) {
        let initials = Conversation(contactName: name, contactNumber: "").initials
        let usable = !isNumberOnly && initials.first?.isLetter == true
        label.stringValue = usable ? initials : ""
        label.isHidden = !usable
        icon.isHidden = usable
    }
}

private final class ConversationRowCell: NSTableCellView {
    private let avatar = AvatarView(size: 40)
    private let nameLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(wrappingLabelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let unreadDot = NSView()
    private let pinGlyph = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        unreadDot.wantsLayer = true
        unreadDot.layer?.cornerRadius = 4
        unreadDot.layer?.backgroundColor = NSColor.droidAccent.cgColor

        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.font = .systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        snippetLabel.font = .systemFont(ofSize: 12)
        snippetLabel.textColor = .secondaryLabelColor
        snippetLabel.maximumNumberOfLines = 2
        snippetLabel.lineBreakMode = .byTruncatingTail
        snippetLabel.cell?.truncatesLastVisibleLine = true
        snippetLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        pinGlyph.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        pinGlyph.symbolConfiguration = .init(pointSize: 9, weight: .semibold)
        pinGlyph.contentTintColor = .systemOrange

        [unreadDot, avatar, nameLabel, timeLabel, snippetLabel, pinGlyph].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        textField = nameLabel

        NSLayoutConstraint.activate([
            unreadDot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            unreadDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            unreadDot.widthAnchor.constraint(equalToConstant: 8),
            unreadDot.heightAnchor.constraint(equalToConstant: 8),

            avatar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            avatar.centerYAnchor.constraint(equalTo: centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: pinGlyph.leadingAnchor, constant: -4),
            pinGlyph.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            pinGlyph.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -4),

            timeLabel.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),

            snippetLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
            snippetLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            snippetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            snippetLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(with conv: Conversation) {
        avatar.configure(name: conv.contactName, isNumberOnly: conv.contactName == conv.contactNumber)
        nameLabel.stringValue = conv.contactName
        snippetLabel.stringValue = (conv.lastMessage?.body ?? "").replacingOccurrences(of: "\n", with: " ")
        timeLabel.stringValue = conv.lastMessage.map { ListTime.string($0.timestamp) } ?? ""
        unreadDot.isHidden = !SMSStore.shared.isUnread(conv)
        pinGlyph.isHidden = !SMSStore.shared.isPinned(conv)
    }
}

private enum ListTime {
    static func string(_ date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        if cal.isDateInToday(date) { f.timeStyle = .short; f.dateStyle = .none; return f.string(from: date) }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        if let days = cal.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            f.dateFormat = "EEEE"; return f.string(from: date)
        }
        f.dateStyle = .short; f.timeStyle = .none
        return f.string(from: date)
    }
}

/// One chat bubble, pinned left (incoming, grey) or right (outgoing, blue).
private final class BubbleRow: NSView {
    init(message: Message, maxWidth: CGFloat) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let bubble = NSView()
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 17
        bubble.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubble)

        let label = NSTextField(wrappingLabelWithString: message.body)
        label.font = .systemFont(ofSize: 14)
        label.isSelectable = true
        label.preferredMaxLayoutWidth = maxWidth - 24
        label.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(label)

        let outgoing = !message.isIncoming
        if outgoing {
            bubble.layer?.backgroundColor = (message.deliveryStatus == .failed ? NSColor.systemRed : NSColor.droidAccent).cgColor
            bubble.alphaValue = message.deliveryStatus == .pending ? 0.6 : 1
            label.textColor = .white
        } else {
            bubble.layer?.backgroundColor = NSColor(name: nil) { a in
                a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 1)
                    : NSColor(srgbRed: 0.91, green: 0.91, blue: 0.92, alpha: 1)
            }.resolvedCGColor(in: self)
            label.textColor = .labelColor
        }
        toolTip = Self.tip.string(from: message.timestamp)

        NSLayoutConstraint.activate([
            bubble.topAnchor.constraint(equalTo: topAnchor),
            bubble.bottomAnchor.constraint(equalTo: bottomAnchor),
            bubble.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            outgoing ? bubble.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
                     : bubble.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            outgoing ? bubble.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 60)
                     : bubble.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -60),
            label.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -7),
            label.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -12)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private static let tip: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
    }()
}

private extension NSColor {
    func resolvedCGColor(in view: NSView) -> CGColor {
        var c: CGColor = cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { c = self.cgColor }
        return c
    }
}

/// "Today 8:31 PM" between groups of messages.
private final class DateSeparator: NSView {
    init(date: Date) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: Self.text(date))
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private static func text(_ date: Date) -> String {
        let cal = Calendar.current
        let time = DateFormatter(); time.timeStyle = .short; time.dateStyle = .none
        if cal.isDateInToday(date) { return "Today \(time.string(from: date))" }
        if cal.isDateInYesterday(date) { return "Yesterday \(time.string(from: date))" }
        let f = DateFormatter(); f.dateFormat = "EEE, d MMM 'at' h:mm a"
        return f.string(from: date)
    }
}

/// "Sent" / "Not Delivered" under the last outgoing bubble.
private final class StatusCaption: NSView {
    init(text: String, failed: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = failed ? .systemRed : .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
}

/// Centered icon + text (+ optional button) for empty and error states of the list.
private final class StatusOverlay: NSView {
    var onButton: (() -> Void)?
    private let icon = NSImageView()
    private let spinner = NSProgressIndicator()
    private let title = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.symbolConfiguration = .init(pointSize: 28, weight: .light)
        icon.contentTintColor = .tertiaryLabelColor
        spinner.style = .spinning
        spinner.controlSize = .small
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .tertiaryLabelColor
        detail.alignment = .center
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(tapped)

        let stack = NSStackView(views: [icon, spinner, title, detail, button])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            detail.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(symbol: String?, title t: String, detail d: String?, button b: String?, spinning: Bool = false) {
        isHidden = false
        icon.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        icon.isHidden = symbol == nil
        spinner.isHidden = !spinning
        spinning ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        title.stringValue = t
        detail.stringValue = d ?? ""
        detail.isHidden = d == nil
        button.title = b ?? ""
        button.isHidden = b == nil
    }

    @objc private func tapped() { onButton?() }
}
