import AppKit

setvbuf(stdout, nil, _IOLBF, 0) // line-buffer logs even when piped to a file

// Single-instance guard: two engines both reacting to every From change
// means double signature-menu blinks (and retry crossfire). The lock is
// held for the process's lifetime and released automatically on exit.
try? FileManager.default.createDirectory(at: ConfigStore.directory, withIntermediateDirectories: true)
let lockFD = open(ConfigStore.directory.appendingPathComponent(".ottograph.lock").path, O_CREAT | O_RDWR, 0o644)
if lockFD == -1 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    print("Another Ottograph is already running — exiting.")
    exit(1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
app.run()
