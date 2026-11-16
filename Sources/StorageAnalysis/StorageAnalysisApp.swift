import SwiftUI
import StorageAnalysisCore

@main
struct StorageAnalysisApp: App {
    init() {
        // Menu-bar only: no Dock icon even when run outside the .app bundle
        // (the bundle also sets LSUIElement).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
        } label: {
            // Phase 1: static placeholder. Phase 6 wires real free space (PLAN.md §5.5).
            Text("⚠︎ — GB")
        }
        .menuBarExtraStyle(.window)
    }
}
