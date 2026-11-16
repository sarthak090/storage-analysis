import SwiftUI
import StorageAnalysisCore

@main
struct StorageAnalysisApp: App {
    @State private var model = ScanModel()

    init() {
        // Menu-bar only: no Dock icon even when run outside the .app bundle
        // (the bundle also sets LSUIElement).
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            let label = model.menuBarLabel
            HStack(spacing: 3) {
                Image(systemName: label.symbol)
                Text(label.text)
            }
            // The label exists from launch, so this runs one scan at startup.
            // Further scans only happen when you press Rescan.
            .task { await model.scan() }
            .help(model.diskSpace.map(Format.spaceSummary) ?? "Storage Analysis")
            .accessibilityLabel(model.diskSpace.map(Format.spaceSummary) ?? "Storage Analysis")
        }
        .menuBarExtraStyle(.window)
    }
}
