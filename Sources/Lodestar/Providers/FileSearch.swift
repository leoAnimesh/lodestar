import AppKit
import LodestarCore

/// File search backed by the Spotlight index (NSMetadataQuery), scoped to
/// the user's home folder.
final class FileSearchScreen: ListScreen {
    let title = "Search Files"
    let placeholder = "Search files by name…"
    weak var host: ScreenHost?

    private var query: NSMetadataQuery?
    private var observer: NSObjectProtocol?
    private var debounce: DispatchWorkItem?
    private var currentText = ""

    func search(_ text: String) -> [LauncherItem] {
        currentText = text
        debounce?.cancel()
        guard text.trimmingCharacters(in: .whitespaces).count >= 2 else {
            stopQuery()
            return []
        }
        let work = DispatchWorkItem { [weak self] in self?.startQuery(text) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        return []
    }

    private func startQuery(_ text: String) {
        stopQuery()
        let q = NSMetadataQuery()
        q.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, text)
        q.searchScopes = [NSMetadataQueryUserHomeScope]
        q.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSContentChangeDateKey, ascending: false)]
        observer = NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidFinishGathering, object: q, queue: .main
        ) { [weak self] _ in self?.publishResults() }
        query = q
        q.start()
    }

    private func publishResults() {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }
        var paths: [String] = []
        for i in 0..<min(q.resultCount, 300) {
            if let item = q.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                paths.append(path)
            }
        }
        // Re-rank Spotlight hits by name quality, keeping recency as tiebreak order.
        let text = currentText
        let scored = paths.enumerated().compactMap { idx, path -> (String, Double, [Int])? in
            let name = (path as NSString).lastPathComponent
            guard let m = FuzzyMatcher.match(text, in: name) else { return nil }
            return (path, m.score - Double(idx) * 0.01, m.matchedIndices)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(60)

        let home = NSHomeDirectory()
        let items = scored.map { path, _, indices -> LauncherItem in
            let display = path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
            return LauncherItem(
                id: "file:\(path)",
                title: (path as NSString).lastPathComponent,
                subtitle: (display as NSString).deletingLastPathComponent,
                icon: .file(path),
                actions: [
                    LauncherAction("Open", symbol: "arrow.up.forward.app") { SystemActions.open(URL(fileURLWithPath: path)); return .close },
                    LauncherAction("Reveal in Finder", symbol: "folder") { SystemActions.reveal(path); return .close },
                    LauncherAction("Copy Path", symbol: "doc.on.doc") { SystemActions.copy(path); return .toast("Path copied") },
                ],
                matchedIndices: indices,
                tracksUsage: false
            )
        }
        host?.setItems(Array(items), for: self)
    }

    private func stopQuery() {
        query?.stop()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        query = nil
    }

    func dismissed() {
        debounce?.cancel()
        stopQuery()
    }
}
