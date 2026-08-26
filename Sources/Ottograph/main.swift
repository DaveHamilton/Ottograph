import AppKit

setvbuf(stdout, nil, _IOLBF, 0) // line-buffer logs even when piped to a file

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
