import SwiftUI
import LodestarCore

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent("Open Lodestar") {
                    HStack(spacing: 6) {
                        HotkeyRecorderView(model: model)
                        if !model.isRecording && !model.hotkey.isSameShortcut(as: .default) {
                            Button {
                                model.restoreDefault()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.borderless)
                            .help("Restore \(HotkeySpec.default.description)")
                        }
                    }
                }
                if let error = model.hotkeyError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } header: {
                Text("Shortcut")
            } footer: {
                Text(model.isRecording
                     ? "Press the new shortcut. Esc cancels, Delete restores \(HotkeySpec.default.description)."
                     : "Click the shortcut to record a new one. Changes apply immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin == .enabled || model.launchAtLogin == .requiresApproval },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .disabled(model.launchAtLogin == .unavailable)
                if model.launchAtLogin == .requiresApproval {
                    HStack {
                        Text("Allow Lodestar in System Settings › General › Login Items.")
                            .font(.callout)
                        Spacer()
                        Button("Open…") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let error = model.launchAtLoginError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } header: {
                Text("General")
            } footer: {
                Text(model.launchAtLogin == .unavailable
                     ? "Launch at login is only available when running the bundled Lodestar.app (./scripts/bundle.sh), not via swift run."
                     : "Uses the system Login Items list. Only works from the bundled Lodestar.app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep clipboard history", isOn: Binding(
                    get: { model.clipboardHistoryEnabled },
                    set: { model.setClipboardHistoryEnabled($0) }
                ))
                Stepper(value: Binding(
                    get: { model.clipboardHistoryLimit },
                    set: { model.setClipboardHistoryLimit($0) }
                ), in: 50...2000, step: 50) {
                    LabeledContent("Entries kept", value: "\(model.clipboardHistoryLimit)")
                }
                .disabled(!model.clipboardHistoryEnabled)
                if let error = model.configError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } header: {
                Text("Clipboard History")
            } footer: {
                Text("Clipboard changes take effect the next time Lodestar starts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Other options live in config.json.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Config Folder") {
                        NSWorkspace.shared.open(LodestarPaths.configDirectory)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A shortcut field: click to record, then press a combo.
struct HotkeyRecorderView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Button {
            model.toggleRecording()
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(model.isRecording && model.recordingPreview.isEmpty ? .secondary : .primary)
                .frame(minWidth: 120)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(model.isRecording ? 0.04 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(model.isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shortcut to open Lodestar")
        .accessibilityValue(model.isRecording ? "Recording" : model.hotkey.description)
        .accessibilityHint(model.isRecording ? "Press the new shortcut, or Escape to cancel" : "Click to record a new shortcut")
    }

    private var label: String {
        guard model.isRecording else { return model.hotkey.description }
        return model.recordingPreview.isEmpty ? "Type shortcut…" : model.recordingPreview + "…"
    }
}
