import AppKit

@MainActor
final class UsageProviderChooser: NSObject {
    let alert = NSAlert()
    private let codexCheckbox = NSButton(checkboxWithTitle: "Codex", target: nil, action: nil)
    private let claudeCheckbox = NSButton(checkboxWithTitle: "Claude", target: nil, action: nil)
    private let selectionHint = NSTextField(labelWithString: "")

    init(current: UsageProviderSelection?) {
        super.init()
        alert.messageText = "Choose your menu bar items"
        alert.informativeText = "Choose one or both providers. Each gets its own usage panel."
        alert.addButton(withTitle: "Show usage")
        alert.addButton(withTitle: "Cancel")

        let providers = (current ?? .both).providers
        for (provider, checkbox) in [(UsageProvider.codex, codexCheckbox), (.claude, claudeCheckbox)] {
            checkbox.state = providers.contains(provider) ? .on : .off
            checkbox.font = .systemFont(ofSize: 14, weight: .medium)
            checkbox.target = self
            checkbox.action = #selector(selectionChanged)
            checkbox.setAccessibilityHelp("Show \(provider.title) usage in its own menu bar item.")
        }
        selectionHint.font = .systemFont(ofSize: 12)
        selectionHint.textColor = .secondaryLabelColor

        let choices = NSStackView(views: [codexCheckbox, claudeCheckbox, selectionHint])
        choices.orientation = .vertical
        choices.alignment = .leading
        choices.spacing = 12
        choices.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 88))
        content.addSubview(choices)
        NSLayoutConstraint.activate([
            choices.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            choices.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            choices.topAnchor.constraint(equalTo: content.topAnchor, constant: 4),
            choices.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -4)
        ])
        alert.accessoryView = content
        selectionChanged()
        alert.window.initialFirstResponder = codexCheckbox
    }

    func runModal() -> UsageProviderSelection? {
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return selection
    }

    private var selection: UsageProviderSelection? {
        switch (codexCheckbox.state == .on, claudeCheckbox.state == .on) {
        case (true, true): .both
        case (true, false): .codex
        case (false, true): .claude
        case (false, false): nil
        }
    }

    @objc private func selectionChanged() {
        let count = selection?.providers.count ?? 0
        alert.buttons.first?.isEnabled = count > 0
        selectionHint.stringValue = switch count {
        case 0: "Select at least one provider."
        case 1: "1 menu bar item selected"
        default: "2 menu bar items selected"
        }
    }
}
