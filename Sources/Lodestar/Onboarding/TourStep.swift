import AppKit
import SwiftUI
import LodestarCore

/// An interactive tour: pick a feature on the left, then type into a working
/// miniature launcher on the right. Search and clipboard filtering
/// use the real fuzzy matcher, and the calculator is the real evaluator.
struct TourStep: View {
    enum Feature: Int, CaseIterable, Identifiable {
        case search, actions, clipboard, calculator
        var id: Int { rawValue }

        var title: String {
            switch self {
            case .search: return "Search"
            case .actions: return "Actions"
            case .clipboard: return "Clipboard History"
            case .calculator: return "Calculator"
            }
        }

        var symbol: String {
            switch self {
            case .search: return "magnifyingglass"
            case .actions: return "command"
            case .clipboard: return "doc.on.clipboard"
            case .calculator: return "equal.square"
            }
        }

        var tint: Color {
            switch self {
            case .search: return .blue
            case .actions: return .pink
            case .clipboard: return .orange
            case .calculator: return .green
            }
        }

        var tip: String {
            switch self {
            case .search: return "Type a few letters of any app or command. Initials work too: “ss” finds System Settings."
            case .actions: return "Every result has more than one action. Press ⌘K to see them all, or ⌘↩ for the second one."
            case .clipboard: return "Open “Clipboard History” to search what you copied earlier, then press ↩ to paste it."
            case .calculator: return "Type math straight into the search bar. ↩ copies the answer, ⌘↩ pastes it."
            }
        }

        var sampleQuery: String {
            switch self {
            case .search: return "cal"
            case .actions: return "saf"
            case .clipboard: return ""
            case .calculator: return "1280 / 16 * 9"
            }
        }

        var hints: [(String, String)] {
            switch self {
            case .search: return [("Open", "↩"), ("Move", "↑↓")]
            case .actions: return [("Actions", "⌘K"), ("Second action", "⌘↩")]
            case .clipboard: return [("Paste", "↩"), ("Copy", "⌘↩")]
            case .calculator: return [("Copy", "↩"), ("Paste", "⌘↩")]
            }
        }
    }

    @ObservedObject var state: OnboardingState
    @State private var query = Feature.search.sampleQuery
    private var feature: Feature { Feature(rawValue: state.tourFeature) ?? .search }
    private var showActions: Bool {
        get { state.tourShowActions }
        nonmutating set { state.tourShowActions = newValue }
    }
    @State private var selected = 0
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Take a quick tour").font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Pick a feature and try typing. This is a working preview.")
                    .font(.system(size: 13.5)).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 4) {
                    ForEach(Feature.allCases) { f in
                        Button { select(f) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: f.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(f.tint.gradient))
                                Text(f.title).font(.system(size: 13, weight: feature == f ? .semibold : .regular))
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(feature == f ? Color.primary.opacity(0.09) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Text(feature.tip)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(feature)
                }
                .frame(width: 210)

                miniLauncher
            }
            .padding(.horizontal, 32)
            Spacer(minLength: 0)
        }
        .onAppear { query = feature.sampleQuery; fieldFocused = true }
        .onChange(of: state.tourFeature) { _ in query = feature.sampleQuery; selected = 0 }
    }

    private func select(_ f: Feature) {
        state.tourFeature = f.rawValue
        query = f.sampleQuery
        showActions = false
        selected = 0
        fieldFocused = true
    }

    // MARK: Mini launcher

    private var miniLauncher: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                LodestarStarIcon(size: 16, lineWidth: 1.4).foregroundStyle(.secondary)
                if feature == .clipboard {
                    Text("Clipboard History")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
                }
                TextField(feature == .clipboard ? "Search clipboard…" : "Search apps and commands…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16, weight: .light))
                    .focused($fieldFocused)
                    .onChange(of: query) { _ in selected = 0 }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            Divider().opacity(0.5)
            ZStack(alignment: .bottomTrailing) {
                results
                if showActions, let item = rows.indices.contains(selected) ? rows[selected] : nil {
                    actionPanel(for: item)
                        .padding(8)
                        .transition(.scale(scale: 0.95, anchor: .bottomTrailing).combined(with: .opacity))
                }
            }
            .frame(height: 232)
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                Text("Lodestar").foregroundStyle(.tertiary)
                Spacer()
                ForEach(Array(feature.hints.enumerated()), id: \.offset) { _, h in
                    HStack(spacing: 4) {
                        Text(h.0).foregroundStyle(.secondary)
                        Text(h.1)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
        .background(VisualEffectBackground(material: .popover, blending: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        .background(
            // Hidden buttons give the preview real keyboard handling.
            Group {
                Button("") { withAnimation(.easeOut(duration: 0.15)) { showActions.toggle() } }
                    .keyboardShortcut("k", modifiers: .command)
                Button("") { if !rows.isEmpty { selected = (selected + 1) % rows.count } }
                    .keyboardShortcut(.downArrow, modifiers: [])
                Button("") { if !rows.isEmpty { selected = (selected - 1 + rows.count) % rows.count } }
                    .keyboardShortcut(.upArrow, modifiers: [])
            }
            .opacity(0)
            .allowsHitTesting(false)
        )
    }

    private var results: some View { list }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                if rows.isEmpty {
                    Text(feature == .calculator ? "Type a calculation, like 2^10" : "No results")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                        .padding(.top, 70)
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                    ResultRow(item: item, selected: index == selected)
                        .scaleEffect(0.92, anchor: .leading)
                        .frame(height: 38)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selected = index
                            if feature == .actions { withAnimation { showActions = true } }
                        }
                }
            }
            .padding(6)
        }
    }

    private func actionPanel(for item: LauncherItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
            ForEach(Array(TourStep.sampleActions.enumerated()), id: \.offset) { i, a in
                HStack(spacing: 8) {
                    Image(systemName: a.1).frame(width: 16)
                    Text(a.0)
                    Spacer()
                    if i == 0 { Text("↩").foregroundStyle(.secondary) }
                    if i == 1 { Text("⌘↩").foregroundStyle(.secondary) }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 5).fill(i == 0 ? Color.accentColor.opacity(0.2) : .clear).padding(.horizontal, 4))
            }
            .padding(.bottom, 4)
        }
        .frame(width: 220)
        .background(VisualEffectBackground(material: .menu, blending: .withinWindow))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }

    static let sampleActions = [("Open Application", "arrow.up.forward.app"), ("Reveal in Finder", "folder"),
                                ("Copy Path", "doc.on.doc"), ("Quit Application", "xmark.circle")]

    // MARK: Data

    private var rows: [LauncherItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        switch feature {
        case .search, .actions:
            let commands: [(String, ItemIcon, String)] = [
                ("Clipboard History", .tinted("doc.on.clipboard", IconTint.forItem("cmd:clipboard")), "Command"),
                ("Search Files", .tinted("doc.text.magnifyingglass", IconTint.forItem("cmd:files")), "Command"),
                ("Toggle Dark Mode", .tinted("circle.lefthalf.filled", IconTint.forItem("sys:dark")), "System"),
            ]
            let apps = TourStep.sampleApps.map { ($0.name, ItemIcon.file($0.path), "Application") }
            return fuzzy(apps + commands, q, limitWhenEmpty: 6)
        case .clipboard:
            let entries = TourStep.sampleClipboard.map { ($0.0, ItemIcon.symbol("doc.text"), $0.1) }  // entries, not commands: plain
            return fuzzy(entries, q, limitWhenEmpty: 8, keepOrder: true)
        case .calculator:
            guard let value = Calculator.evaluateIfCalculation(q) else { return [] }
            return [LauncherItem(id: "calc", title: Calculator.format(value), subtitle: "= \(q)", icon: .tinted("equal", IconTint.forItem("calc")),
                                 accessory: "Calculator", actions: [])]
        }
    }

    private func fuzzy(_ source: [(String, ItemIcon, String)], _ q: String, limitWhenEmpty: Int, keepOrder: Bool = false) -> [LauncherItem] {
        if q.isEmpty {
            return source.prefix(limitWhenEmpty).map { LauncherItem(id: $0.0, title: $0.0, icon: $0.1, accessory: $0.2, actions: []) }
        }
        var scored: [(LauncherItem, Double)] = []
        for s in source {
            guard let m = FuzzyMatcher.match(q, in: s.0) else { continue }
            var item = LauncherItem(id: s.0, title: s.0, icon: s.1, accessory: s.2, actions: [])
            item.matchedIndices = m.matchedIndices
            scored.append((item, keepOrder ? 0 : m.score))
        }
        if !keepOrder { scored.sort { $0.1 > $1.1 } }
        return scored.prefix(8).map(\.0)
    }

    /// Common apps that ship with macOS; icons come from the user's own system.
    static let sampleApps: [(name: String, path: String)] = {
        let candidates = [
            ("Calendar", "/System/Applications/Calendar.app"), ("Calculator", "/System/Applications/Calculator.app"),
            ("Safari", "/Applications/Safari.app"), ("Notes", "/System/Applications/Notes.app"),
            ("Music", "/System/Applications/Music.app"), ("Maps", "/System/Applications/Maps.app"),
            ("System Settings", "/System/Applications/System Settings.app"), ("Terminal", "/System/Applications/Utilities/Terminal.app"),
            ("Reminders", "/System/Applications/Reminders.app"), ("Photos", "/System/Applications/Photos.app"),
        ]
        return candidates.filter { FileManager.default.fileExists(atPath: $0.1) }.map { (name: $0.0, path: $0.1) }
    }()

    static let sampleClipboard: [(String, String)] = [
        ("Standup moved to 10:30 tomorrow", "2m ago"),
        ("https://example.com/handbook/onboarding", "8m ago"),
        ("brew install ripgrep fd", "21m ago"),
        ("#6B66FA", "1h ago"),
        ("SELECT name, email FROM users WHERE active = 1;", "3h ago"),
        ("Thanks! I'll send the draft over tonight.", "Yesterday"),
    ]
}
