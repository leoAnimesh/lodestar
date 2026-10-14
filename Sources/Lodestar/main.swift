import AppKit

// Writing to an extension whose process already exited would otherwise
// raise SIGPIPE and kill the app; we handle the write error instead.
signal(SIGPIPE, SIG_IGN)

// Build-time helper used by scripts/bundle.sh: render the app icon as an
// .iconset folder (the art is drawn in code; see UI/Brand.swift) and exit.
if let i = CommandLine.arguments.firstIndex(of: "--render-icon"), CommandLine.arguments.indices.contains(i + 1) {
    let dir = URL(fileURLWithPath: CommandLine.arguments[i + 1])
    do {
        try MainActor.assumeIsolated { try LodestarMark.writeIconset(to: dir) }
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("render-icon failed: \(error)\n".utf8))
        exit(1)
    }
}

let app = NSApplication.shared
// Accessory: no Dock icon or app menu; lives in the menu bar.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
