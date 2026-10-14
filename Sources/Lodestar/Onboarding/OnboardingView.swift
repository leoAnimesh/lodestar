import AppKit
import SwiftUI
import LodestarCore

struct OnboardingView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var state: OnboardingState
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .underWindowBackground)
            // Soft color wash behind the content.
            RadialGradient(colors: [Color.lodestarAccent.opacity(0.28), .clear],
                           center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Color(red: 0.98, green: 0.55, blue: 0.36).opacity(0.12), .clear],
                           center: UnitPoint(x: 0.9, y: 1.1), startRadius: 0, endRadius: 420)

            VStack(spacing: 0) {
                ZStack {
                    page
                        .id(state.step)
                        .transition(.asymmetric(
                            insertion: .offset(x: CGFloat(state.direction) * 40).combined(with: .opacity),
                            removal: .offset(x: CGFloat(-state.direction) * 40).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 28)
                .animation(.spring(response: 0.38, dampingFraction: 0.9), value: state.step)

                bottomBar
            }
        }
        // Fill the whole window, including the transparent title bar area.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var page: some View {
        switch state.step {
        case .welcome: WelcomeStep()
        case .hotkey: HotkeyStep(model: model, capture: model.capture)
        case .permissions: PermissionsStep(permissions: model.permissions)
        case .startup: StartupStep(model: model)
        case .tour: TourStep(state: state)
        case .done: DoneStep(model: model)
        }
    }

    private var bottomBar: some View {
        ZStack {
            HStack(spacing: 7) {
                ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                    Capsule()
                        .fill(s == state.step ? Color.primary.opacity(0.8) : Color.primary.opacity(0.2))
                        .frame(width: s == state.step ? 18 : 7, height: 7)
                        .onTapGesture { if s.rawValue < state.step.rawValue { state.go(to: s) } }
                        .accessibilityLabel("Step \(s.rawValue + 1) of \(OnboardingStep.allCases.count)")
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: state.step)

            HStack {
                if !state.isFirst {
                    Button("Back") { model.capture.cancel(); state.back() }
                        .buttonStyle(OnboardingButtonStyle(prominent: false))
                }
                Spacer()
                Button(state.step.primaryTitle) {
                    model.capture.cancel()
                    if state.isLast { onFinish() } else { state.next() }
                }
                .buttonStyle(OnboardingButtonStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 72)
    }
}

struct OnboardingButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .frame(minWidth: prominent ? 120 : 80, minHeight: 32)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Color.lodestarAccent.gradient) : AnyShapeStyle(Color.primary.opacity(0.08)))
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(prominent ? 0.18 : 0)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

/// Title + subtitle used at the top of most steps.
private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            LodestarMark(size: 128)
                .shadow(color: Color.lodestarAccent.opacity(0.55), radius: 30, y: 10)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            VStack(spacing: 10) {
                Text("Welcome to Lodestar")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text("Everything on your Mac, one keystroke away.")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text("Open apps, run commands, search your clipboard and paste emoji without reaching for the mouse. Setup takes about a minute.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Spacer()
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.05)) { appeared = true } }
    }
}

private struct HotkeyStep: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var capture: ShortcutCapture

    private var recording: Bool { capture.isRecording(SettingsModel.launcherTarget) }

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "Choose your shortcut",
                       subtitle: "This opens Lodestar from any app. Pick something easy to reach that you don't use for anything else.")
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(recording ? Color.lodestarAccent : Color.primary.opacity(0.08), lineWidth: recording ? 2 : 1))
                if recording {
                    VStack(spacing: 8) {
                        if capture.preview.isEmpty {
                            Text("Press your new shortcut").font(.system(size: 17, weight: .medium)).foregroundStyle(.secondary)
                        } else {
                            KeycapRow(parts: capture.preview.map(String.init), size: 24)
                        }
                        Text("Esc cancels · Delete restores \(HotkeySpec.default.description)")
                            .font(.system(size: 11.5)).foregroundStyle(.tertiary)
                    }
                } else {
                    KeycapRow(parts: model.hotkey.keycapParts, size: 26)
                }
            }
            .frame(width: 360, height: 120)
            .contentShape(Rectangle())
            .onTapGesture { model.toggleLauncherRecording() }

            HStack(spacing: 10) {
                Button(recording ? "Cancel" : "Record New Shortcut") { model.toggleLauncherRecording() }
                if !recording && !model.hotkey.isSameShortcut(as: .default) {
                    Button("Use \(HotkeySpec.default.description)") { model.restoreDefaultHotkey() }
                }
            }

            VStack(spacing: 8) {
                if let error = model.hotkeyError { InlineMessage(kind: .error, text: error) }
                if let warning = model.hotkeyWarning {
                    HStack(alignment: .top, spacing: 10) {
                        InlineMessage(kind: .warning, text: warning)
                        Button("Keyboard Shortcuts…") { PermissionsMonitor.openKeyboardShortcuts() }.controlSize(.small)
                    }
                } else {
                    InlineMessage(kind: .info, text: "Prefer ⌘Space? Spotlight already uses it, so turn Spotlight's shortcut off in System Settings › Keyboard first.")
                }
            }
            .frame(maxWidth: 500)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
}

private struct PermissionsStep: View {
    @ObservedObject var permissions: PermissionsMonitor

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(title: "Grant permissions",
                       subtitle: "Some features need your OK in System Settings. Statuses update here as soon as you change them.")
            Card(padding: 14) {
                PermissionRow(symbol: "hand.raised.fill", tint: .blue, title: "Accessibility",
                              detail: "Paste from clipboard history and emoji into other apps, and Lock Screen.",
                              status: permissions.accessibility, buttonTitle: "Grant Access…") {
                    permissions.requestAccessibility()
                }
                Divider()
                PermissionRow(symbol: "gearshape.2.fill", tint: .purple, title: "Automation",
                              detail: "Run system commands such as Sleep, Lock Screen and Toggle Dark Mode.",
                              status: permissions.automation, buttonTitle: "Allow…") {
                    permissions.requestAutomation()
                }
                Divider()
                PermissionRow(symbol: "externaldrive.fill", tint: .gray, title: "Full Disk Access",
                              detail: "Let file search reach folders macOS protects, such as Mail.",
                              status: permissions.fullDiskAccess, optional: true, buttonTitle: "Open Settings…") {
                    PermissionsMonitor.open(.fullDiskAccess)
                }
            }
            .frame(maxWidth: 600)
            Text("You can skip this and grant access later in Settings › Advanced.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
}

private struct StartupStep: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(title: "Always ready",
                       subtitle: "Lodestar lives in your menu bar and uses very little memory while it waits for your shortcut.")
            Card(padding: 16) {
                HStack(spacing: 14) {
                    icon("power", .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login").font(.system(size: 13, weight: .semibold))
                        Text(model.launchAtLogin == .unavailable
                             ? "Available in the bundled Lodestar.app (./scripts/bundle.sh)."
                             : "Start Lodestar automatically when you log in.")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.launchAtLoginIsOn }, set: { model.setLaunchAtLogin($0) }))
                        .toggleStyle(.switch).labelsHidden()
                        .disabled(model.launchAtLogin == .unavailable)
                }
                if model.launchAtLogin == .requiresApproval {
                    HStack {
                        InlineMessage(kind: .warning, text: "Approve Lodestar in System Settings › General › Login Items.")
                        Button("Open…") { LaunchAtLogin.openLoginItemsSettings() }.controlSize(.small)
                    }
                }
                if let error = model.launchAtLoginError { InlineMessage(kind: .error, text: error) }
                Divider()
                HStack(spacing: 14) {
                    icon("menubar.rectangle", .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in menu bar").font(.system(size: 13, weight: .semibold))
                        Text("Quick access to Settings and this welcome screen.")
                            .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.showMenuBarIcon }, set: { model.setShowMenuBarIcon($0) }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            .frame(maxWidth: 520)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private func icon(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
    }
}

private struct DoneStep: View {
    @ObservedObject var model: SettingsModel
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle().fill(Color.lodestarAccent.opacity(0.18)).frame(width: 120, height: 120)
                    .scaleEffect(appeared ? 1 : 0.6)
                GuideStar(waist: 0.2)
                    .fill(LinearGradient(colors: [.white, Color.lodestarAccent], startPoint: .top, endPoint: .bottom))
                    .frame(width: 70, height: 70)
                    .shadow(color: Color.lodestarAccent.opacity(0.7), radius: 14)
                    .rotationEffect(.degrees(appeared ? 0 : -45))
            }
            VStack(spacing: 10) {
                Text("You're all set").font(.system(size: 30, weight: .bold, design: .rounded))
                HStack(spacing: 8) {
                    Text("Press").foregroundStyle(.secondary)
                    KeycapRow(parts: model.hotkey.keycapParts, size: 15)
                    Text("to start, from any app.").foregroundStyle(.secondary)
                }
                .font(.system(size: 15))
            }
            HStack(spacing: 18) {
                tip("command", "⌘,", "Settings")
                tip("questionmark.circle", "Menu bar", "Show Welcome…")
                tip("command.square", "⌘K", "Actions")
            }
            .padding(.top, 6)
            Spacer()
        }
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { appeared = true } }
    }

    private func tip(_ symbol: String, _ key: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(key).font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(width: 120, height: 52)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
    }
}
