import AppKit
import SwiftUI
import LodestarCore

/// The Settings window: a centered icon tab bar over a page per tab.
struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().opacity(0.6)
            Group {
                switch model.selectedTab {
                case .general: GeneralSettingsPage(model: model)
                case .extensions: ExtensionsSettingsPage(model: model)
                case .clipboard: ClipboardSettingsPage(model: model)
                case .advanced: AdvancedSettingsPage(model: model, permissions: model.permissions)
                case .about: AboutSettingsPage(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .underWindowBackground))
        .ignoresSafeArea()
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                TabButton(tab: tab, selected: model.selectedTab == tab) {
                    model.capture.cancel()
                    model.selectedTab = tab
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
    }
}

private struct TabButton: View {
    let tab: SettingsTab
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(height: 22)
                Text(tab.title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            .frame(width: 76, height: 50)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.09 : hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - General

struct GeneralSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var capture: ShortcutCapture

    init(model: SettingsModel) {
        self.model = model
        self.capture = model.capture
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SettingsRow(label: "Lodestar Hotkey") {
                    HStack(spacing: 6) {
                        ShortcutField(capture: capture, target: SettingsModel.launcherTarget, spec: model.hotkey) {
                            model.toggleLauncherRecording()
                        }
                        if !capture.isRecording && !model.hotkey.isSameShortcut(as: .default) {
                            Button { model.restoreDefaultHotkey() } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.borderless)
                                .help("Restore \(HotkeySpec.default.description)")
                        }
                    }
                    if let error = model.hotkeyError { InlineMessage(kind: .error, text: error) }
                    if let warning = model.hotkeyWarning { InlineMessage(kind: .warning, text: warning) }
                    Footnote(capture.isRecording(SettingsModel.launcherTarget)
                             ? "Press the new shortcut. Esc cancels, Delete restores \(HotkeySpec.default.description)."
                             : "The shortcut that opens the launcher from anywhere. Changes apply immediately.")
                }

                SettingsRow(label: "Startup") {
                    Toggle("Launch Lodestar at login", isOn: Binding(
                        get: { model.launchAtLoginIsOn }, set: { model.setLaunchAtLogin($0) }))
                        .disabled(model.launchAtLogin == .unavailable)
                    if model.launchAtLogin == .requiresApproval {
                        HStack {
                            InlineMessage(kind: .warning, text: "Waiting for approval in System Settings › General › Login Items.")
                            Button("Open…") { LaunchAtLogin.openLoginItemsSettings() }.controlSize(.small)
                        }
                    }
                    if let error = model.launchAtLoginError { InlineMessage(kind: .error, text: error) }
                    if model.launchAtLogin == .unavailable {
                        Footnote("Only available in the bundled Lodestar.app (./scripts/bundle.sh), not with swift run.")
                    }
                }

                Divider().padding(.leading, 216)

                SettingsRow(label: "Appearance") {
                    Picker("", selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                        ForEach(AppearanceMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Footnote("Applies to the launcher, Settings and the welcome window.")
                }

                SettingsRow(label: "Launcher Position", alignment: .top) {
                    HStack(spacing: 12) {
                        ForEach(LauncherPosition.allCases, id: \.self) { position in
                            PositionChoice(position: position, selected: model.launcherPosition == position) {
                                model.setLauncherPosition(position)
                            }
                        }
                    }
                    Footnote("Where the launcher appears on the screen that has the pointer.")
                }

                SettingsRow(label: "Menu Bar") {
                    Toggle("Show Lodestar in the menu bar", isOn: Binding(
                        get: { model.showMenuBarIcon }, set: { model.setShowMenuBarIcon($0) }))
                    Footnote(model.showMenuBarIcon
                             ? "The menu bar icon opens the launcher, Settings and the welcome screen."
                             : "Hidden. Open Settings with ⌘, in the launcher or the “Lodestar Settings” command. Opening Lodestar.app again shows the launcher.")
                }

                if let error = model.configError {
                    SettingsRow(label: "") { InlineMessage(kind: .error, text: error) }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A tiny screen diagram for the launcher position choice.
private struct PositionChoice: View {
    let position: LauncherPosition
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(selected ? 0.9 : 0.45))
                        .frame(width: 50, height: 22)
                        .padding(.top, position == .upperThird ? 12 : 23)
                }
                .frame(width: 92, height: 68)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
                Text(position.title).font(.system(size: 11)).foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Launcher position: \(position.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Clipboard

struct ClipboardSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmClear = false
    private let limits = [50, 100, 300, 500, 1000, 2000]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(symbol: "doc.on.clipboard", tint: .orange, title: "Clipboard History",
                           subtitle: "Lodestar remembers text, links, colors, images and files you copy so you can find and paste them later.")

                SettingsRow(label: "History") {
                    Toggle("Keep clipboard history", isOn: Binding(
                        get: { model.clipboardHistoryEnabled }, set: { model.setClipboardHistoryEnabled($0) }))
                    Footnote("Turning this off stops recording right away. Saved entries stay until you clear them.")
                }

                SettingsRow(label: "Keep up to") {
                    Picker("", selection: Binding(get: { model.clipboardHistoryLimit }, set: { model.setClipboardHistoryLimit($0) })) {
                        ForEach(Array(Set(limits + [model.clipboardHistoryLimit])).sorted(), id: \.self) { Text("\($0) entries").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    .disabled(!model.clipboardHistoryEnabled)
                    Footnote("The oldest entries are removed once the limit is reached. Pinned entries are kept.")
                }

                SettingsRow(label: "Saved Entries") {
                    HStack(spacing: 10) {
                        Text("\(model.clipboardCount)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Button("Clear History…") { confirmClear = true }
                            .disabled(model.clipboardCount == 0)
                    }
                }

                Divider().padding(.leading, 216)

                SettingsRow(label: "Privacy") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("lock.shield", "Items that password managers mark as concealed or temporary are skipped.")
                        bullet("internaldrive", "Stored only on this Mac, readable by your user only, in ~/Library/Application Support/Lodestar (clipboard.json, plus images in the clipboard folder). Deleting an entry deletes its image.")
                        bullet("keyboard", "Open it from the launcher with the “Clipboard History” command. Return pastes, ⌘K shows more actions, ⌘P filters by type.")
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
        }
        .alert("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear", role: .destructive) { model.clearClipboardHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(model.clipboardCount) saved entries.")
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 460, alignment: .leading)
    }
}

/// Big icon + title at the top of a page.
struct PageHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 70)
        .padding(.bottom, 4)
    }
}

// MARK: - Advanced

struct AdvancedSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var permissions: PermissionsMonitor
    @State private var confirmReset = false
    @State private var onboardingReset = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle("Permissions")
                Card(padding: 12) {
                    PermissionRow(symbol: "hand.raised.fill", tint: .blue, title: "Accessibility",
                                  detail: "Pasting from clipboard history and emoji into other apps, and Lock Screen.",
                                  status: permissions.accessibility, buttonTitle: "Grant Access…") {
                        permissions.requestAccessibility()
                    }
                    Divider()
                    PermissionRow(symbol: "gearshape.2.fill", tint: .purple, title: "Automation",
                                  detail: "System commands such as Sleep, Empty Trash and Toggle Dark Mode.",
                                  status: permissions.automation, buttonTitle: "Allow…") {
                        permissions.requestAutomation()
                    }
                    Divider()
                    PermissionRow(symbol: "externaldrive.fill", tint: .gray, title: "Full Disk Access",
                                  detail: "Lets file search reach folders macOS protects, such as Mail.",
                                  status: permissions.fullDiskAccess, optional: true, buttonTitle: "Open Settings…") {
                        PermissionsMonitor.open(.fullDiskAccess)
                    }
                }
                Footnote("Statuses update live. Lodestar never changes these for you; buttons open the system prompt or the matching System Settings pane.")

                sectionTitle("Files")
                Card(padding: 12) {
                    pathRow("Config file", LodestarPaths.configFile, isFile: true)
                    Divider()
                    pathRow("Script commands", LodestarPaths.scriptsDirectory)
                    Divider()
                    pathRow("Extensions", LodestarPaths.extensionsDirectory)
                    Divider()
                    pathRow("App data", LodestarPaths.supportDirectory)
                }

                sectionTitle("Reset")
                Card(padding: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Welcome screen").font(.system(size: 13, weight: .medium))
                            Text(onboardingReset ? "It will open the next time Lodestar starts." : "Walk through setup and the feature tour again.")
                                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset") {
                            UserDefaults.standard.removeObject(forKey: Onboarding.completedVersionKey)
                            onboardingReset = true
                        }
                        .disabled(onboardingReset)
                        Button("Show Now") { model.showOnboarding() }
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Command settings").font(.system(size: 13, weight: .medium))
                            Text("Re-enable every command and remove all aliases and command hotkeys.")
                                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reset…") { confirmReset = true }
                            .disabled(model.preferences.configValue == nil)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
        }
        .alert("Reset all command settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetCommandSettings() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Disabled commands come back, and aliases and command hotkeys are removed.")
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold)).padding(.top, 4)
    }

    private func pathRow(_ title: String, _ url: URL, isFile: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isFile ? "doc.text" : "folder").foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text((url.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Reveal") {
                if isFile && !FileManager.default.fileExists(atPath: url.path) {
                    NSWorkspace.shared.open(url.deletingLastPathComponent())
                } else {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .controlSize(.small)
            if isFile {
                Button("Open") {
                    if !FileManager.default.fileExists(atPath: url.path) { try? Data("{}\n".utf8).write(to: url) }
                    NSWorkspace.shared.open(url)
                }
                .controlSize(.small)
            }
        }
    }
}

// MARK: - About

struct AboutSettingsPage: View {
    @ObservedObject var model: SettingsModel
    @State private var showLicense = false

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        guard let short else { return "Development build" }
        return build.map { $0 == short ? "Version \(short)" : "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    static var licenseText: String {
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
           let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        return "MIT License\n\nCopyright (c) 2026 Lodestar contributors\n\nSee the LICENSE file in the source repository for the full text."
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            LodestarMark(size: 104)
                .shadow(color: Color.lodestarAccent.opacity(0.35), radius: 18, y: 6)
            VStack(spacing: 4) {
                Text("Lodestar").font(.system(size: 26, weight: .bold, design: .rounded))
                Text(AboutSettingsPage.version).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
            }
            Text("A fast, open-source launcher for your Mac.\nFind apps, run commands and paste emoji without leaving the keyboard.")
                .multilineTextAlignment(.center)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("View License") { showLicense = true }
                Button("Show Welcome Screen") { model.showOnboarding() }
            }
            .padding(.top, 6)
            Spacer()
            Text("Released under the MIT License · © 2026 Lodestar contributors\nAn independent project, not affiliated with any other launcher.")
                .multilineTextAlignment(.center)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showLicense) {
            VStack(alignment: .leading, spacing: 12) {
                Text("License").font(.headline)
                ScrollView {
                    Text(AboutSettingsPage.licenseText)
                        .font(.system(size: 11.5, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack { Spacer(); Button("Done") { showLicense = false }.keyboardShortcut(.defaultAction) }
            }
            .padding(20)
            .frame(width: 520, height: 420)
        }
    }
}
