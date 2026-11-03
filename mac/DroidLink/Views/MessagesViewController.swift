//
//  MessagesViewController.swift
//  DroidLink
//
//  Created for DroidLink macOS Client.
//  Copyright © 2026 DroidLink. All rights reserved.
//

import AppKit

/// Messages view controller synchronizing Android SMS/MMS conversations with native macOS styling,
/// real-time incoming call alerts, and inline text composition.
public final class MessagesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private var conversations: [Conversation] = Conversation.mockConversations
    private var selectedConversation: Conversation? = Conversation.mockConversations.first
    private var searchQuery: String = ""

    private var callBanner: NSView!
    private var splitView: NSSplitView!
    private var conversationsTableView: NSTableView!
    private var messagesTableView: NSTableView!
    private var searchField: NSSearchField!

    private var recipientTitleLabel: NSTextField!
    private var recipientSubLabel: NSTextField!
    private var composeTextField: NSTextField!

    private var filteredConversations: [Conversation] {
        if searchQuery.isEmpty {
            return conversations
        } else {
            return conversations.filter {
                $0.contactName.localizedCaseInsensitiveContains(searchQuery) ||
                $0.contactNumber.contains(searchQuery)
            }
        }
    }

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        self.view = root

        setupCallBanner()
        setupSplitView()

        NSLayoutConstraint.activate([
            callBanner.topAnchor.constraint(equalTo: root.topAnchor),
            callBanner.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            callBanner.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            callBanner.heightAnchor.constraint(equalToConstant: 60),

            splitView.topAnchor.constraint(equalTo: callBanner.bottomAnchor),
            splitView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    // MARK: - Incoming Call Banner

    private func setupCallBanner() {
        callBanner = NSView()
        callBanner.wantsLayer = true
        callBanner.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        callBanner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(callBanner)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        callBanner.addSubview(sep)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        callBanner.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: callBanner.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: callBanner.trailingAnchor, constant: -18),
            stack.centerYAnchor.constraint(equalTo: callBanner.centerYAnchor),

            sep.leadingAnchor.constraint(equalTo: callBanner.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: callBanner.trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: callBanner.bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1)
        ])

        let icon = NSImageView(image: NSImage(systemSymbolName: "phone.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemGreen
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 24).isActive = true
        stack.addArrangedSubview(icon)

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2

        let callTitle = NSTextField(labelWithString: "Incoming Call: Sarah Connor")
        callTitle.font = .systemFont(ofSize: 13, weight: .bold)
        labelStack.addArrangedSubview(callTitle)

        let callSub = NSTextField(labelWithString: "+1 (555) 234-5678")
        callSub.font = .systemFont(ofSize: 11)
        callSub.textColor = .secondaryLabelColor
        labelStack.addArrangedSubview(callSub)

        stack.addArrangedSubview(labelStack)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)

        let declineBtn = NSButton(title: "Decline", target: self, action: #selector(declineCallClicked(_:)))
        declineBtn.bezelStyle = .rounded
        stack.addArrangedSubview(declineBtn)

        let acceptBtn = NSButton(title: "Accept", target: self, action: #selector(acceptCallClicked(_:)))
        acceptBtn.bezelStyle = .rounded
        acceptBtn.keyEquivalent = "\r"
        stack.addArrangedSubview(acceptBtn)
    }

    @objc private func declineCallClicked(_ sender: NSButton) {
        callBanner.isHidden = true
    }

    @objc private func acceptCallClicked(_ sender: NSButton) {
        callBanner.isHidden = true
    }

    // MARK: - Split View

    private func setupSplitView() {
        splitView = NSSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)

        // Left Pane: Conversations
        let leftPane = createConversationsPane()
        leftPane.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
        splitView.addSubview(leftPane)

        // Right Pane: Thread View
        let rightPane = createThreadPane()
        splitView.addSubview(rightPane)

        splitView.setPosition(280, ofDividerAt: 0)
    }

    private func createConversationsPane() -> NSView {
        let pane = NSView()

        let searchContainer = NSView()
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(searchContainer)

        searchField = NSSearchField()
        searchField.placeholderString = "Search contacts..."
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(scroll)

        conversationsTableView = NSTableView()
        conversationsTableView.headerView = nil
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ConversationCol"))
        conversationsTableView.addTableColumn(col)
        conversationsTableView.dataSource = self
        conversationsTableView.delegate = self
        conversationsTableView.rowHeight = 60
        scroll.documentView = conversationsTableView

        NSLayoutConstraint.activate([
            searchContainer.topAnchor.constraint(equalTo: pane.topAnchor),
            searchContainer.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            searchContainer.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            searchContainer.heightAnchor.constraint(equalToConstant: 44),

            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

            scroll.topAnchor.constraint(equalTo: searchContainer.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: pane.bottomAnchor)
        ])

        return pane
    }

    private func createThreadPane() -> NSView {
        let pane = NSView()

        // Header
        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        header.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(header)

        let sepTop = NSBox()
        sepTop.boxType = .separator
        sepTop.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(sepTop)

        let labelStack = NSStackView()
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(labelStack)

        recipientTitleLabel = NSTextField(labelWithString: selectedConversation?.contactName ?? "")
        recipientTitleLabel.font = .systemFont(ofSize: 14, weight: .bold)
        labelStack.addArrangedSubview(recipientTitleLabel)

        recipientSubLabel = NSTextField(labelWithString: selectedConversation?.contactNumber ?? "")
        recipientSubLabel.font = .systemFont(ofSize: 11)
        recipientSubLabel.textColor = .secondaryLabelColor
        labelStack.addArrangedSubview(recipientSubLabel)

        // Messages scroll / table
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(scroll)

        messagesTableView = NSTableView()
        messagesTableView.headerView = nil
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("MessageCol"))
        messagesTableView.addTableColumn(col)
        messagesTableView.dataSource = self
        messagesTableView.delegate = self
        messagesTableView.selectionHighlightStyle = .none
        messagesTableView.rowHeight = 56
        scroll.documentView = messagesTableView

        // Compose bar at bottom
        let composeBar = NSView()
        composeBar.wantsLayer = true
        composeBar.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        composeBar.translatesAutoresizingMaskIntoConstraints = false
        pane.addSubview(composeBar)

        let sepBottom = NSBox()
        sepBottom.boxType = .separator
        sepBottom.translatesAutoresizingMaskIntoConstraints = false
        composeBar.addSubview(sepBottom)

        composeTextField = NSTextField()
        composeTextField.placeholderString = "Type a message..."
        composeTextField.target = self
        composeTextField.action = #selector(sendMessageClicked(_:))
        composeTextField.translatesAutoresizingMaskIntoConstraints = false
        composeBar.addSubview(composeTextField)

        let sendBtn = NSButton(title: "Send", target: self, action: #selector(sendMessageClicked(_:)))
        sendBtn.bezelStyle = .rounded
        sendBtn.keyEquivalent = "\r"
        sendBtn.translatesAutoresizingMaskIntoConstraints = false
        composeBar.addSubview(sendBtn)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: pane.topAnchor),
            header.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 48),

            labelStack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            labelStack.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            sepTop.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            sepTop.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            sepTop.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            sepTop.heightAnchor.constraint(equalToConstant: 1),

            scroll.topAnchor.constraint(equalTo: header.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: composeBar.topAnchor),

            composeBar.leadingAnchor.constraint(equalTo: pane.leadingAnchor),
            composeBar.trailingAnchor.constraint(equalTo: pane.trailingAnchor),
            composeBar.bottomAnchor.constraint(equalTo: pane.bottomAnchor),
            composeBar.heightAnchor.constraint(equalToConstant: 52),

            sepBottom.leadingAnchor.constraint(equalTo: composeBar.leadingAnchor),
            sepBottom.trailingAnchor.constraint(equalTo: composeBar.trailingAnchor),
            sepBottom.topAnchor.constraint(equalTo: composeBar.topAnchor),
            sepBottom.heightAnchor.constraint(equalToConstant: 1),

            composeTextField.leadingAnchor.constraint(equalTo: composeBar.leadingAnchor, constant: 16),
            composeTextField.centerYAnchor.constraint(equalTo: composeBar.centerYAnchor),
            composeTextField.trailingAnchor.constraint(equalTo: sendBtn.leadingAnchor, constant: -12),

            sendBtn.trailingAnchor.constraint(equalTo: composeBar.trailingAnchor, constant: -16),
            sendBtn.centerYAnchor.constraint(equalTo: composeBar.centerYAnchor)
        ])

        return pane
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        searchQuery = sender.stringValue
        conversationsTableView.reloadData()
    }

    @objc private func sendMessageClicked(_ sender: Any) {
        let text = composeTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let conv = selectedConversation else { return }

        let newMsg = Message(
            conversationId: conv.id,
            contactName: conv.contactName,
            contactNumber: conv.contactNumber,
            body: text,
            timestamp: Date(),
            isIncoming: false,
            deliveryStatus: .sent
        )

        if let index = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[index].messages.append(newMsg)
            selectedConversation = conversations[index]
        }

        composeTextField.stringValue = ""
        messagesTableView.reloadData()
        conversationsTableView.reloadData()
    }

    // MARK: - NSTableViewDataSource & Delegate

    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView == conversationsTableView {
            return filteredConversations.count
        } else {
            return selectedConversation?.messages.count ?? 0
        }
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableView == conversationsTableView {
            guard row < filteredConversations.count else { return nil }
            let conv = filteredConversations[row]

            let cellId = NSUserInterfaceItemIdentifier("ConversationCell")
            let cell: ConversationRowCell
            if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? ConversationRowCell {
                cell = reused
            } else {
                cell = ConversationRowCell()
                cell.identifier = cellId
            }
            cell.configure(with: conv)
            return cell
        } else {
            guard let messages = selectedConversation?.messages, row < messages.count else { return nil }
            let msg = messages[row]

            let cellId = NSUserInterfaceItemIdentifier("MessageBubbleCell")
            let cell: MessageBubbleCell
            if let reused = tableView.makeView(withIdentifier: cellId, owner: nil) as? MessageBubbleCell {
                cell = reused
            } else {
                cell = MessageBubbleCell()
                cell.identifier = cellId
            }
            cell.configure(with: msg)
            return cell
        }
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView, table == conversationsTableView else { return }
        let selectedRow = table.selectedRow
        guard selectedRow >= 0 && selectedRow < filteredConversations.count else { return }

        selectedConversation = filteredConversations[selectedRow]
        recipientTitleLabel.stringValue = selectedConversation?.contactName ?? ""
        recipientSubLabel.stringValue = selectedConversation?.contactNumber ?? ""
        messagesTableView.reloadData()
    }
}

// MARK: - Conversation Row Cell

private final class ConversationRowCell: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let snippetLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let avatarView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        avatarView.image = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil)
        avatarView.contentTintColor = .systemBlue
        avatarView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(avatarView)

        nameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        snippetLabel.font = .systemFont(ofSize: 11)
        snippetLabel.textColor = .secondaryLabelColor
        snippetLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(snippetLabel)

        timeLabel.font = .systemFont(ofSize: 10)
        timeLabel.textColor = .tertiaryLabelColor
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        let sep = NSBox()
        sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sep)

        NSLayoutConstraint.activate([
            avatarView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            avatarView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarView.widthAnchor.constraint(equalToConstant: 32),
            avatarView.heightAnchor.constraint(equalToConstant: 32),

            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),

            timeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            snippetLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            snippetLabel.leadingAnchor.constraint(equalTo: avatarView.trailingAnchor, constant: 10),
            snippetLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),

            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: trailingAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.heightAnchor.constraint(equalToConstant: 1)
        ])
    }

    func configure(with conv: Conversation) {
        nameLabel.stringValue = conv.contactName
        snippetLabel.stringValue = conv.lastMessage?.body ?? ""
        timeLabel.stringValue = conv.lastMessage?.formattedTime ?? ""
    }
}

// MARK: - Message Bubble Cell

private final class MessageBubbleCell: NSTableCellView {
    private let bubbleView = NSView()
    private let messageLabel = NSTextField(labelWithString: "")
    private var leadingConstraint: NSLayoutConstraint?
    private var trailingConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = 14
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubbleView)

        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.maximumNumberOfLines = 4
        bubbleView.addSubview(messageLabel)

        leadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        trailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)

        NSLayoutConstraint.activate([
            bubbleView.centerYAnchor.constraint(equalTo: centerYAnchor),
            bubbleView.widthAnchor.constraint(lessThanOrEqualToConstant: 340),

            messageLabel.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: 8),
            messageLabel.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor, constant: -8),
            messageLabel.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -12)
        ])
    }

    func configure(with msg: Message) {
        messageLabel.stringValue = msg.body

        if !msg.isIncoming {
            bubbleView.layer?.backgroundColor = NSColor.systemBlue.cgColor
            messageLabel.textColor = .white
            leadingConstraint?.isActive = false
            trailingConstraint?.isActive = true
        } else {
            bubbleView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            messageLabel.textColor = .labelColor
            trailingConstraint?.isActive = false
            leadingConstraint?.isActive = true
        }
    }
}
