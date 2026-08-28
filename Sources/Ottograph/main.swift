import AppKit

setvbuf(stdout, nil, _IOLBF, 0) // line-buffer logs even when piped to a file

// Single-instance guard: two engines both reacting to every From change
// means double signature-menu blinks (and retry crossfire). The lock is
// held for the process's lifetime and released automatically on exit.
try? FileManager.default.createDirectory(at: ConfigStore.directory, withIntermediateDirectories: true)
let lockFD = open(ConfigStore.directory.appendingPathComponent(".ottograph.lock").path, O_CREAT | O_RDWR, 0o644)
if lockFD == -1 || flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    // Logged as well as printed: launched from Finder there is no stdout,
    // and a second copy exiting on sight is exactly the sort of silence
    // that reads as "the app won't start".
    Log.engine.error("Another Ottograph is already running — exiting.")
    print("Another Ottograph is already running — exiting.")
    exit(1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
    app.run() // never returns; `delegate` lives for the app's lifetime
}
