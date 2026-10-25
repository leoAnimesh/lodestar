import AppKit
import SwiftUI
import LodestarCore

/// The "Software Update" window: check progress, the new version's notes,
/// and Install & Relaunch / Skip This Version / Later.
final class UpdateWindowController: NSObject, NSWindowDelegate {
    let manager: UpdateManager

    init(manager: UpdateManager) {
        self.manager = manager
    }

    private(set) lazy var window: NSWindow = {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 460),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Software Update"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.delegate = self
        let host = NSHostingView(rootView: UpdateView(manager: manager, close: { [weak window] in window?.performClose(nil) }))
        window.contentView = host
        window.center()
        return window
    }()

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Closing during a check or on an offer means "later"; a download keeps going
        // only while the window is open.
        manager.later()
    }
}

struct UpdateView: View {
    @ObservedObject var manager: UpdateManager
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                LodestarMark(size: 64)
                    .shadow(color: Color.lodestarAccent.opacity(0.3), radius: 10, y: 4)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 26)
            .padding(.top, 34)
            .padding(.bottom, 18)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 26)

            Divider().padding(.top, 16)
            footer
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        .frame(width: 600, height: 460)
        .background(VisualEffectBackground(material: .windowBackground, blending: .behindWindow))
    }

    // MARK: Text

    private var title: String {
        switch manager.phase {
        case .idle, .checking: return "Checking for updates…"
        case .upToDate: return "You're up to date"
        case .available: return "A new version of Lodestar is available"
        case .downloading: return "Downloading the update…"
        case .verifying: return "Verifying the update…"
        case .installing: return "Installing…"
        case .failed: return manager.release == nil ? "Couldn't check for updates" : "Couldn't install the update"
        }
    }

    private var subtitle: String {
        let current = manager.currentVersion == nil ? "a development build" : manager.currentVersionText
        switch manager.phase {
        case .idle, .checking: return "Asking GitHub for the latest release. You have \(manager.currentVersion == nil ? current : "Lodestar " + current)."
        case .upToDate:
            return "Lodestar \(manager.currentVersionText) is the newest version\(manager.includePrereleases ? " (including pre-releases)" : "")."
        case .available:
            guard let r = manager.release else { return "" }
            return "Lodestar \(r.version) is available — you have \(current)."
                + (r.isPrerelease ? " This is a pre-release." : "")
        case .downloading, .verifying, .installing:
            return "Lodestar will relaunch by itself when it's done."
        case .failed: return "Nothing was changed."
        }
    }

    // MARK: Body

    @ViewBuilder private var content: some View {
        switch manager.phase {
        case .idle, .checking:
            HStack { Spacer(); ProgressView().controlSize(.regular); Spacer() }.padding(.top, 60)
        case .upToDate:
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
                if let date = manager.lastChecked {
                    Text("Checked \(date.formatted(.relative(presentation: .named)))").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 50)
        case .available:
            VStack(alignment: .leading, spacing: 10) {
                notes
                if let blocker = manager.installBlocker {
                    InlineMessage(kind: .info, text: blocker + " Use the release page to download it.")
                } else if manager.release?.isInstallable == false {
                    InlineMessage(kind: .info, text: "This release can't be installed automatically. Use the release page to download it.")
                }
            }
        case .downloading(let received, let total):
            VStack(alignment: .leading, spacing: 10) {
                notes
                progress(fraction: total.map { $0 > 0 ? Double(received) / Double($0) : 0 },
                         label: total.map { "\(Self.bytes(received)) of \(Self.bytes($0))" } ?? Self.bytes(received))
            }
        case .verifying:
            VStack(alignment: .leading, spacing: 10) { notes; progress(fraction: nil, label: "Checking the SHA-256 checksum and code signature…") }
        case .installing:
            VStack(alignment: .leading, spacing: 10) { notes; progress(fraction: nil, label: "Replacing the app and relaunching…") }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                InlineMessage(kind: .error, text: message)
                if manager.release != nil { notes }
            }
        }
    }

    private func progress(fraction: Double?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let fraction { ProgressView(value: min(max(fraction, 0), 1)) } else { ProgressView().progressViewStyle(.linear) }
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private var notes: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                let blocks = ReleaseNotes.blocks(from: manager.release?.notes ?? "")
                if blocks.isEmpty {
                    Text("No release notes were provided.").foregroundStyle(.secondary)
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    switch block {
                    case .heading(let level, let text):
                        Text(Self.inline(text))
                            .font(.system(size: level <= 2 ? 14 : 12.5, weight: .semibold))
                            .padding(.top, 4)
                    case .bullet(let text):
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("•").foregroundStyle(.secondary)
                            Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
                        }
                    case .paragraph(let text):
                        Text(Self.inline(text)).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .font(.system(size: 12.5))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    static func inline(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(markdown)
    }

    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    // MARK: Footer

    @ViewBuilder private var footer: some View {
        HStack(spacing: 10) {
            switch manager.phase {
            case .available:
                Button("Skip This Version") { manager.skipThisVersion(); close() }
                Spacer()
                Button("Later") { close() }.keyboardShortcut(.cancelAction)
                if manager.installBlocker == nil, manager.release?.isInstallable == true {
                    Button("Install & Relaunch") { manager.installUpdate() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Open Release Page") { manager.openReleasePage(); close() }.keyboardShortcut(.defaultAction)
                }
            case .downloading:
                Button("Release Notes on GitHub") { manager.openReleasePage() }.buttonStyle(.link)
                Spacer()
                Button("Cancel") { manager.cancelDownload() }.keyboardShortcut(.cancelAction)
            case .verifying, .installing:
                Spacer()
                Button("Install & Relaunch") {}.disabled(true)
            case .failed:
                if manager.release != nil {
                    Button("Open Release Page") { manager.openReleasePage(); close() }
                }
                Spacer()
                if manager.release != nil {
                    Button("Try Again") { manager.installUpdate() }
                } else {
                    Button("Try Again") { manager.checkForUpdates(userInitiated: true) }
                }
                Button("Close") { close() }.keyboardShortcut(.defaultAction)
            case .idle, .checking, .upToDate:
                Button("Releases on GitHub") { NSWorkspace.shared.open(UpdateFeed.releasesPage) }.buttonStyle(.link)
                Spacer()
                Button(manager.phase == .upToDate ? "OK" : "Cancel") { close() }.keyboardShortcut(.defaultAction)
            }
        }
    }
}
