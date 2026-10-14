import AppKit

// Writing to an extension whose process already exited would otherwise
// raise SIGPIPE and kill the app; we handle the write error instead.
signal(SIGPIPE, SIG_IGN)

let app = NSApplication.shared
// Accessory: no Dock icon or app menu; lives in the menu bar.
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
