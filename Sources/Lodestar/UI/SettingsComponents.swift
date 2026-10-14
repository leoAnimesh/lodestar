import SwiftUI
import LodestarCore

/// A two-column settings row: a right-aligned label, then the control.
struct SettingsRow<Content: View>: View {
    let label: String
    var labelWidth: CGFloat = 200
    /// Use `.top` when the control's first line isn't text (e.g. a picture grid).
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: alignment, spacing: 16) {
            Text(label)
                .foregroundStyle(.secondary)
                .padding(.top, alignment == .top ? 4 : 0)
                .frame(width: labelWidth, alignment: .trailing)
            VStack(alignment: .leading, spacing: 6) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Small grey help text under a control.
struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 440, alignment: .leading)
    }
}

struct InlineMessage: View {
    enum Kind { case error, warning, info }
    let kind: Kind
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: kind == .info ? "info.circle.fill" : "exclamationmark.triangle.fill")
        }
        .font(.system(size: 11.5))
        .foregroundStyle(kind == .error ? Color.red : kind == .warning ? Color.orange : Color.secondary)
        .frame(maxWidth: 440, alignment: .leading)
    }
}

/// A rounded group box used on the Settings pages.
struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

/// A click-to-record shortcut field bound to a `ShortcutCapture` target.
struct ShortcutField: View {
    @ObservedObject var capture: ShortcutCapture
    let target: String
    let spec: HotkeySpec?
    var placeholder = "Record Shortcut"
    var compact = false
    let onToggle: () -> Void

    private var recording: Bool { capture.isRecording(target) }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 4) {
                if recording {
                    Text(capture.preview.isEmpty ? "Type shortcut…" : capture.preview + "…")
                        .foregroundStyle(capture.preview.isEmpty ? .secondary : .primary)
                } else if let spec {
                    Text(spec.description)
                } else {
                    Text(placeholder).foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: compact ? 11.5 : 13, weight: .medium, design: .rounded))
            .lineLimit(1)
            .frame(minWidth: compact ? 84 : 128)
            .padding(.horizontal, compact ? 6 : 10)
            .padding(.vertical, compact ? 3 : 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(recording ? 0.03 : (spec == nil && compact ? 0 : 0.08))))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(spec == nil && compact ? 0.1 : 0), lineWidth: recording ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shortcut")
        .accessibilityValue(recording ? "Recording" : spec?.description ?? "None")
        .help(recording ? "Press a shortcut. Esc cancels, Delete clears." : "Click to record a shortcut")
    }
}

/// A status pill such as "Granted" (green) or "Not Granted" (orange).
struct StatusPill: View {
    let status: PermissionsMonitor.Status
    var optional = false

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(status.label).font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
        .foregroundStyle(color == .secondary ? Color.secondary : color)
    }

    private var color: Color {
        switch status {
        case .granted: return .green
        case .denied, .notDetermined: return optional ? .secondary : .orange
        case .unknown: return .secondary
        }
    }
}

/// One permission: icon, explanation, live status and a button.
struct PermissionRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let status: PermissionsMonitor.Status
    var optional = false
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if optional {
                        Text("Optional").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
                    }
                }
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            StatusPill(status: status, optional: optional)
            if status != .granted {
                Button(buttonTitle, action: action).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
