// BTT-Plugin-Name: Quick Links
// BTT-Plugin-Identifier: com.folivora.launcher.quicklinks.example
// BTT-Plugin-Type: Launcher
// BTT-Plugin-Icon: link.badge.plus
// BTT-Principal-Class: QuickLinkLauncherPlugin
// BTT-AI-Managed: true

import AppKit
import Foundation
import SwiftUI

final class QuickLinkLauncherPlugin: NSObject, BTTLauncherPluginInterface {
    weak var delegate: (any BTTLauncherPluginDelegate)?

    static let pluginIdentifier = "com.folivora.launcher.quicklinks.example"

    private enum IDs {
        static let createItem = "create-quick-link"
        static let editorSurface = "quick-link-editor"
    }

    private enum Actions {
        static let open = "open"
        static let copyURL = "copy-url"
        static let duplicate = "duplicate"
        static let delete = "delete"
    }

    static func launcherPluginName() -> String {
        "Quick Links"
    }

    static func launcherPluginDescription() -> String {
        "Create saved launcher items that open reusable URL templates."
    }

    static func launcherPluginIcon() -> String {
        "link.badge.plus"
    }

    func launcherResults(for context: BTTLauncherPluginContext) -> [BTTLauncherPluginResult]? {
        let result = BTTLauncherPluginResult()
        result.itemIdentifier = IDs.createItem
        result.title = "Create Quick Link"
        result.subtitle = "Save a reusable URL template as a launcher item."
        result.systemImageName = "link.badge.plus"
        result.keywords = ["quicklink", "quick link", "url", "bookmark", "browser", "web"]
        result.trailingHint = "Create"
        result.surfaceIdentifier = IDs.editorSurface
        result.searchMatchPriority = NSNumber(value: 50)
        return [result]
    }

    func launcherResult(
        for instance: BTTLauncherPluginInstance,
        context: BTTLauncherPluginContext
    ) -> BTTLauncherPluginResult? {
        let configuration = QuickLinkConfiguration(instance: instance)
        guard !configuration.urlTemplate.isEmpty else { return nil }

        let instanceID = instance.instanceIdentifier ?? UUID().uuidString
        let result = BTTLauncherPluginResult()
        result.itemIdentifier = QuickLinkConfiguration.itemIdentifier(for: instanceID)
        result.title = configuration.name
        result.subtitle = previewSubtitle(for: configuration, context: context)
        result.systemImageName = configuration.systemImageName
        result.keywords = Array(Set(configuration.searchTerms + [
            "quicklink",
            "quick link",
            "link",
            "url",
            configuration.browserName ?? ""
        ] + (instance.keywords ?? []))).filter { !$0.isEmpty }
        result.trailingHint = "Open"
        result.primaryActionIdentifier = Actions.open
        result.surfaceIdentifier = IDs.editorSurface
        result.launcherDisplayMode = NSNumber(value: configuration.displayMode)
        result.commands = [
            command(
                id: Actions.copyURL,
                title: "Copy Resolved URL",
                subtitle: "Copy this quick link after placeholders are filled.",
                systemImageName: "doc.on.doc",
                character: "c",
                modifiers: [.command],
                closesLauncher: false
            ),
            command(
                id: Actions.duplicate,
                title: "Duplicate Quick Link",
                subtitle: "Create another saved item using these settings.",
                systemImageName: "plus.square.on.square",
                character: "d",
                modifiers: [.command],
                closesLauncher: false
            ),
            command(
                id: Actions.delete,
                title: "Delete Quick Link",
                subtitle: "Remove this saved quick link.",
                systemImageName: "trash",
                character: "\u{8}",
                modifiers: [],
                closesLauncher: false,
                destructive: true
            )
        ]
        return result
    }

    func launcherSurface(
        forItemIdentifier itemIdentifier: String,
        surfaceIdentifier: String?,
        context: BTTLauncherPluginContext
    ) -> (any BTTLauncherPluginSurfaceInterface)? {
        guard surfaceIdentifier == IDs.editorSurface else { return nil }
        guard itemIdentifier == IDs.createItem || context.launcherPluginInstance != nil else {
            return nil
        }

        return QuickLinkEditorSurface(
            context: context,
            existingInstance: context.launcherPluginInstance
        )
    }

    func performAction(
        forItemIdentifier itemIdentifier: String,
        actionIdentifier: String?,
        context: BTTLauncherPluginContext
    ) -> BTTLauncherPluginActionResult? {
        let action = actionIdentifier ?? Actions.open
        guard let instance = context.launcherPluginInstance else {
            return actionResult(success: false, message: "No quick link was selected.", closeLauncher: false)
        }

        let configuration = QuickLinkConfiguration(instance: instance)
        guard let resolvedURL = resolvedURL(for: configuration, context: context) else {
            return actionResult(success: false, message: "Could not build a valid URL.", closeLauncher: false)
        }

        switch action {
        case Actions.open:
            open(resolvedURL, browserBundleIdentifier: configuration.browserBundleIdentifier)
            return actionResult(success: true, message: "Opened \(configuration.name).", closeLauncher: true)

        case Actions.copyURL:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(resolvedURL.absoluteString, forType: .string)
            return actionResult(success: true, message: "Copied URL.", closeLauncher: false)

        case Actions.duplicate:
            let duplicate = configuration.instance(existingIdentifier: nil)
            duplicate.title = "\(configuration.name) Copy"
            _ = delegate?.saveLauncherPluginInstance(
                duplicate,
                pluginIdentifier: Self.pluginIdentifier,
                launcherID: context.launcherID
            )
            return actionResult(success: true, message: "Duplicated quick link.", closeLauncher: false)

        case Actions.delete:
            guard let instanceIdentifier = instance.instanceIdentifier else {
                return actionResult(success: false, message: "Could not delete this quick link.", closeLauncher: false)
            }
            delegate?.deleteLauncherPluginInstance(
                instanceIdentifier,
                pluginIdentifier: Self.pluginIdentifier,
                launcherID: context.launcherID
            )
            return actionResult(success: true, message: "Deleted quick link.", closeLauncher: false)

        default:
            return nil
        }
    }

    private func command(
        id: String,
        title: String,
        subtitle: String,
        systemImageName: String,
        character: String,
        modifiers: NSEvent.ModifierFlags,
        closesLauncher: Bool,
        destructive: Bool = false
    ) -> BTTLauncherPluginCommand {
        let shortcut = BTTLauncherPluginShortcut()
        shortcut.character = character
        shortcut.modifierFlags = modifiers
        shortcut.displayKeys = displayKeys(for: character, modifiers: modifiers)

        let command = BTTLauncherPluginCommand()
        command.commandIdentifier = id
        command.title = title
        command.subtitle = subtitle
        command.systemImageName = systemImageName
        command.shortcut = shortcut
        command.closesLauncherOnSuccess = closesLauncher
        command.destructive = destructive
        return command
    }

    private func displayKeys(for character: String, modifiers: NSEvent.ModifierFlags) -> [String] {
        var keys: [String] = []
        if modifiers.contains(.command) { keys.append("Cmd") }
        if modifiers.contains(.option) { keys.append("Option") }
        if modifiers.contains(.control) { keys.append("Control") }
        if modifiers.contains(.shift) { keys.append("Shift") }
        keys.append(character == "\u{8}" ? "Delete" : character.uppercased())
        return keys
    }

    private func resolvedURL(
        for configuration: QuickLinkConfiguration,
        context: BTTLauncherPluginContext
    ) -> URL? {
        let argument = argumentText(for: configuration, context: context, useClipboardFallback: true)
        guard let urlString = resolvedURLString(
            for: configuration,
            context: context,
            argument: argument,
            includeEmptyArgument: true
        ) else {
            return nil
        }
        return URL(string: urlString)
    }

    private func previewSubtitle(
        for configuration: QuickLinkConfiguration,
        context: BTTLauncherPluginContext
    ) -> String {
        let argument = argumentText(for: configuration, context: context, useClipboardFallback: false)
        guard !argument.isEmpty,
              let resolved = resolvedURLString(
                  for: configuration,
                  context: context,
                  argument: argument,
                  includeEmptyArgument: false
              ) else {
            return configuration.urlTemplate
        }
        return resolved
    }

    private func resolvedURLString(
        for configuration: QuickLinkConfiguration,
        context: BTTLauncherPluginContext,
        argument: String,
        includeEmptyArgument: Bool
    ) -> String? {
        let extraVariables = placeholderVariables(
            context: context,
            argument: argument,
            includeEmptyArgument: includeEmptyArgument
        )
        let templateWithPluginVariables = locallyReplaceVariables(
            in: configuration.urlTemplate,
            extraVariables: extraVariables
        )
        let resolvedTemplate = hostReplaceVariables(
            in: templateWithPluginVariables,
            extraVariables: nil
        ) ?? templateWithPluginVariables

        let trimmedURLString = resolvedTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURLString.isEmpty else { return nil }

        if URLComponents(string: trimmedURLString)?.scheme != nil {
            return trimmedURLString
        }
        return "https://\(trimmedURLString)"
    }

    private func hostReplaceVariables(
        in template: String,
        extraVariables: [String: Any]?
    ) -> String? {
        guard let delegateObject = delegate as? NSObject else { return nil }
        let selector = NSSelectorFromString("replaceVariablesInString:extraVariables:")
        guard delegateObject.responds(to: selector) else { return nil }
        return delegateObject
            .perform(selector, with: template, with: extraVariables)
            .takeUnretainedValue() as? String
    }

    private func argumentText(
        for configuration: QuickLinkConfiguration,
        context: BTTLauncherPluginContext,
        useClipboardFallback: Bool
    ) -> String {
        if let query = normalized(context.query) {
            if let remainder = leadingPromptRemainder(query: query, terms: configuration.searchTerms) {
                return remainder
            }
            return query
        }
        guard useClipboardFallback else { return "" }
        return normalized(NSPasteboard.general.string(forType: .string)) ?? ""
    }

    private func leadingPromptRemainder(query: String, terms: [String]) -> String? {
        let lowercasedQuery = query.lowercased()
        for term in terms {
            let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedTerm.isEmpty,
                  lowercasedQuery.count > normalizedTerm.count,
                  lowercasedQuery.hasPrefix(normalizedTerm) else {
                continue
            }
            let suffixIndex = lowercasedQuery.index(lowercasedQuery.startIndex, offsetBy: normalizedTerm.count)
            guard lowercasedQuery[suffixIndex].isWhitespace else { continue }
            return String(query[suffixIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func placeholderVariables(
        context: BTTLauncherPluginContext,
        argument: String,
        includeEmptyArgument: Bool
    ) -> [String: Any] {
        let query = context.query ?? ""
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        let finderURL = context.finderURLs?.first

        var variables: [String: Any] = [
            "clipboard": percentEncoded(clipboard),
            "rawClipboard": clipboard,
            "finderPath": percentEncoded(finderURL?.path ?? ""),
            "rawFinderPath": finderURL?.path ?? "",
            "finderURL": percentEncoded(finderURL?.absoluteString ?? ""),
            "rawFinderURL": finderURL?.absoluteString ?? ""
        ]

        if includeEmptyArgument || !argument.isEmpty {
            variables["argument"] = percentEncoded(argument)
            variables["rawArgument"] = argument
        }
        if !query.isEmpty {
            variables["query"] = percentEncoded(query)
            variables["rawQuery"] = query
        }

        return variables
    }

    private func locallyReplaceVariables(
        in template: String,
        extraVariables: [String: Any]
    ) -> String {
        var resolved = template
        for (key, value) in extraVariables {
            let stringValue = "\(value)"
            resolved = resolved.replacingOccurrences(of: "{{\(key)}}", with: stringValue)
            resolved = resolved.replacingOccurrences(of: "{\(key)}", with: stringValue)
        }
        return resolved
    }

    private func percentEncoded(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=?#/%")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func open(_ url: URL, browserBundleIdentifier: String?) {
        guard let browserBundleIdentifier,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: browserBundleIdentifier) else {
            NSWorkspace.shared.open(url)
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: configuration)
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func actionResult(
        success: Bool,
        message: String?,
        closeLauncher: Bool
    ) -> BTTLauncherPluginActionResult {
        let result = BTTLauncherPluginActionResult()
        result.success = success
        result.message = message
        result.closeLauncher = closeLauncher
        return result
    }
}

private enum QuickLinkDisplayMode: Int, CaseIterable, Identifiable {
    case launcherResult = 1
    case alwaysVisible = 3
    case keywordOnly = 4
    case promptMatchesOnly = 5
    case promptMatchesOrFallback = 6

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .launcherResult:
            return "Show & Filter"
        case .alwaysVisible:
            return "Always Show"
        case .keywordOnly:
            return "Keyword Match"
        case .promptMatchesOnly:
            return "Prompt Match"
        case .promptMatchesOrFallback:
            return "Fallback"
        }
    }
}

private struct QuickLinkConfiguration {
    static let nameKey = "name"
    static let urlTemplateKey = "urlTemplate"
    static let browserBundleIdentifierKey = "browserBundleIdentifier"
    static let browserNameKey = "browserName"
    static let systemImageNameKey = "systemImageName"
    static let displayModeKey = "displayMode"

    var name: String
    var urlTemplate: String
    var browserBundleIdentifier: String?
    var browserName: String?
    var systemImageName: String
    var displayMode: Int

    init(
        name: String = "",
        urlTemplate: String = "https://google.com/search?q={argument}",
        browserBundleIdentifier: String? = nil,
        browserName: String? = nil,
        systemImageName: String = "link",
        displayMode: Int = QuickLinkDisplayMode.keywordOnly.rawValue
    ) {
        self.name = name
        self.urlTemplate = urlTemplate
        self.browserBundleIdentifier = Self.normalized(browserBundleIdentifier)
        self.browserName = Self.normalized(browserName)
        self.systemImageName = Self.normalized(systemImageName) ?? "link"
        self.displayMode = QuickLinkDisplayMode(rawValue: displayMode)?.rawValue ?? QuickLinkDisplayMode.keywordOnly.rawValue
    }

    init(instance: BTTLauncherPluginInstance) {
        let configuration = instance.configuration ?? [:]
        self.init(
            name: Self.normalized(configuration[Self.nameKey] as? String)
                ?? Self.normalized(instance.title)
                ?? "Quick Link",
            urlTemplate: Self.normalized(configuration[Self.urlTemplateKey] as? String)
                ?? Self.normalized(instance.subtitle)
                ?? "",
            browserBundleIdentifier: Self.normalized(configuration[Self.browserBundleIdentifierKey] as? String),
            browserName: Self.normalized(configuration[Self.browserNameKey] as? String),
            systemImageName: Self.normalized(configuration[Self.systemImageNameKey] as? String)
                ?? Self.normalized(instance.systemImageName)
                ?? "link",
            displayMode: (configuration[Self.displayModeKey] as? NSNumber)?.intValue
                ?? instance.launcherDisplayMode?.intValue
                ?? QuickLinkDisplayMode.keywordOnly.rawValue
        )
    }

    var searchTerms: [String] {
        var terms = [name, urlTemplate]
        terms.append(contentsOf: name.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        return terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func itemIdentifier(for instanceIdentifier: String) -> String {
        "instance:\(instanceIdentifier)"
    }

    func instance(existingIdentifier: String?) -> BTTLauncherPluginInstance {
        let instance = BTTLauncherPluginInstance()
        instance.instanceIdentifier = existingIdentifier
        instance.title = name
        instance.subtitle = urlTemplate
        instance.systemImageName = systemImageName
        instance.primaryActionIdentifier = "open"
        instance.surfaceIdentifier = "quick-link-editor"
        instance.launcherDisplayMode = NSNumber(value: displayMode)
        instance.keywords = (searchTerms + [browserName ?? ""]).filter { !$0.isEmpty }
        instance.configuration = [
            Self.nameKey: name,
            Self.urlTemplateKey: urlTemplate,
            Self.browserBundleIdentifierKey: browserBundleIdentifier ?? "",
            Self.browserNameKey: browserName ?? "",
            Self.systemImageNameKey: systemImageName,
            Self.displayModeKey: NSNumber(value: displayMode)
        ]
        return instance
    }

    private static func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private final class QuickLinkEditorSurface: NSObject, BTTLauncherPluginSurfaceInterface {
    weak var delegate: (any BTTLauncherPluginSurfaceDelegate)?

    private let context: BTTLauncherPluginContext
    private let existingInstance: BTTLauncherPluginInstance?
    private let browserChoices = QuickLinkBrowserChoice.installedChoices()
    private var statusText: String?

    init(
        context: BTTLauncherPluginContext,
        existingInstance: BTTLauncherPluginInstance?
    ) {
        self.context = context
        self.existingInstance = existingInstance
        super.init()
    }

    func makeLauncherSurfaceView() -> NSView {
        let draft = QuickLinkEditorDraft(
            configuration: existingInstance.map(QuickLinkConfiguration.init(instance:))
                ?? QuickLinkConfiguration(urlTemplate: initialURLTemplate())
        )
        return NSHostingView(rootView: QuickLinkEditorView(
            isEditing: existingInstance != nil,
            initialDraft: draft,
            browserChoices: browserChoices,
            onSave: { [weak self] draft in
                self?.save(draft)
            },
            onDelete: { [weak self] in
                self?.delete()
            },
            onCancel: { [weak self] in
                self?.delegate?.requestLauncherSurfaceGoBack()
            }
        ))
    }

    func launcherSurfacePreferredContentSize() -> CGSize {
        CGSize(width: 760, height: 560)
    }

    func launcherSurfaceMinimumContentSize() -> CGSize {
        CGSize(width: 620, height: 420)
    }

    func launcherSurfaceKeepsLauncherPinned() -> Bool {
        true
    }

    func launcherSurfacePlaceholderText() -> String? {
        existingInstance == nil ? "Create Quick Link" : "Edit Quick Link"
    }

    func launcherSurfaceFooterHint() -> String? {
        "Use {argument}, {clipboard}, {finderPath}, {finderURL}, or any BTT variable."
    }

    func launcherSurfaceStatusText() -> String? {
        statusText
    }

    private func initialURLTemplate() -> String {
        let query = context.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else {
            return "https://google.com/search?q={argument}"
        }
        if URLComponents(string: query)?.scheme != nil || query.contains(".") {
            return query
        }
        return "https://google.com/search?q={argument}"
    }

    private func save(_ draft: QuickLinkEditorDraft) {
        guard let configuration = draft.configuration(browserChoices: browserChoices) else {
            statusText = "Enter a name and link first."
            delegate?.requestLauncherSurfaceUpdate()
            return
        }

        let instance = configuration.instance(existingIdentifier: existingInstance?.instanceIdentifier)
        _ = delegate?.saveLauncherPluginInstance(
            instance,
            pluginIdentifier: QuickLinkLauncherPlugin.pluginIdentifier,
            launcherID: context.launcherID
        )
        statusText = existingInstance == nil ? "Quick link saved." : "Quick link updated."
        delegate?.requestLauncherSurfaceGoBack()
    }

    private func delete() {
        guard let instanceIdentifier = existingInstance?.instanceIdentifier else { return }
        delegate?.deleteLauncherPluginInstance(
            instanceIdentifier,
            pluginIdentifier: QuickLinkLauncherPlugin.pluginIdentifier,
            launcherID: context.launcherID
        )
        delegate?.requestLauncherSurfaceGoBack()
    }
}

private struct QuickLinkBrowserChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let bundleIdentifier: String?

    static func installedChoices() -> [QuickLinkBrowserChoice] {
        var choices: [QuickLinkBrowserChoice] = [
            QuickLinkBrowserChoice(id: "default", title: defaultBrowserTitle(), bundleIdentifier: nil)
        ]
        let candidates = [
            "com.apple.Safari",
            "com.google.Chrome",
            "com.google.Chrome.canary",
            "org.mozilla.firefox",
            "com.brave.Browser",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",
            "company.thebrowser.dia",
            "company.thebrowser.Dia"
        ]

        var seen = Set<String>()
        for bundleIdentifier in candidates {
            guard !seen.contains(bundleIdentifier),
                  let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                continue
            }
            seen.insert(bundleIdentifier)
            choices.append(QuickLinkBrowserChoice(
                id: bundleIdentifier,
                title: displayName(for: appURL),
                bundleIdentifier: bundleIdentifier
            ))
        }
        return choices
    }

    private static func defaultBrowserTitle() -> String {
        guard let url = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            return "Default Browser"
        }
        return "\(displayName(for: appURL)) (Default)"
    }

    private static func displayName(for appURL: URL) -> String {
        let bundle = Bundle(url: appURL)
        return (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
    }
}

private struct QuickLinkEditorDraft {
    var name: String
    var urlTemplate: String
    var browserChoiceID: String
    var systemImageName: String
    var displayMode: Int

    init(configuration: QuickLinkConfiguration) {
        name = configuration.name
        urlTemplate = configuration.urlTemplate
        browserChoiceID = configuration.browserBundleIdentifier ?? "default"
        systemImageName = configuration.systemImageName
        displayMode = configuration.displayMode
    }

    func configuration(browserChoices: [QuickLinkBrowserChoice]) -> QuickLinkConfiguration? {
        let normalizedName = trimmed(name)
        let normalizedURLTemplate = trimmed(urlTemplate)
        guard !normalizedName.isEmpty, !normalizedURLTemplate.isEmpty else { return nil }

        let browserChoice = browserChoices.first { $0.id == browserChoiceID }
        let iconName = trimmed(systemImageName).isEmpty ? "link" : trimmed(systemImageName)
        return QuickLinkConfiguration(
            name: normalizedName,
            urlTemplate: normalizedURLTemplate,
            browserBundleIdentifier: browserChoice?.bundleIdentifier,
            browserName: browserChoice?.bundleIdentifier == nil ? nil : browserChoice?.title,
            systemImageName: iconName,
            displayMode: displayMode
        )
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct QuickLinkIconChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImageName: String

    static let choices = [
        QuickLinkIconChoice(id: "link", title: "Default", systemImageName: "link"),
        QuickLinkIconChoice(id: "globe", title: "Web", systemImageName: "globe"),
        QuickLinkIconChoice(id: "magnifyingglass", title: "Search", systemImageName: "magnifyingglass"),
        QuickLinkIconChoice(id: "star", title: "Favorite", systemImageName: "star"),
        QuickLinkIconChoice(id: "house", title: "Home", systemImageName: "house"),
        QuickLinkIconChoice(id: "doc.text", title: "Document", systemImageName: "doc.text")
    ]
}

private struct QuickLinkEditorView: View {
    let isEditing: Bool
    let browserChoices: [QuickLinkBrowserChoice]
    let onSave: (QuickLinkEditorDraft) -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @State private var draft: QuickLinkEditorDraft
    @State private var validationMessage: String?

    init(
        isEditing: Bool,
        initialDraft: QuickLinkEditorDraft,
        browserChoices: [QuickLinkBrowserChoice],
        onSave: @escaping (QuickLinkEditorDraft) -> Void,
        onDelete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.isEditing = isEditing
        self.browserChoices = browserChoices
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    formRow("Name") {
                        TextField("Quicklink name", text: $draft.name)
                            .textFieldStyle(.roundedBorder)
                    }

                    formRow("Link") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("https://google.com/search?q={argument}", text: $draft.urlTemplate)
                                .textFieldStyle(.roundedBorder)
                            Text("Use {argument}, {clipboard}, {finderPath}, {finderURL}, or any BTT variable. Use raw variants like {rawArgument} when the value should not be URL-encoded.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    formRow("Open With") {
                        Picker("", selection: $draft.browserChoiceID) {
                            ForEach(browserChoices) { browser in
                                Text(browser.title).tag(browser.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    formRow("Icon") {
                        Picker("", selection: $draft.systemImageName) {
                            ForEach(QuickLinkIconChoice.choices) { icon in
                                Label(icon.title, systemImage: icon.systemImageName)
                                    .tag(icon.systemImageName)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    formRow("Display") {
                        Picker("", selection: $draft.displayMode) {
                            ForEach(QuickLinkDisplayMode.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.leading, 118)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                Label(isEditing ? "Edit Quick Link" : "Create Quick Link", systemImage: "link")
                    .foregroundColor(.secondary)
                Spacer()
                if isEditing {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                }
                Button("Cancel", action: onCancel)
                Button(isEditing ? "Save Quick Link" : "Create Quick Link") {
                    save()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 560)
    }

    private func formRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            content()
        }
    }

    private func save() {
        guard draft.configuration(browserChoices: browserChoices) != nil else {
            validationMessage = "Name and link are required."
            return
        }
        validationMessage = nil
        onSave(draft)
    }
}
