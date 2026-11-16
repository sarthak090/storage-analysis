import SwiftUI
import StorageAnalysisCore

/// Colors and icons shared by the popover.
enum Theme {
    static func color(_ kind: StorageBreakdown.Kind) -> Color {
        switch kind {
        case .safe: .green
        case .rebuild: .orange
        case .risky: .red
        case .other: .secondary.opacity(0.35)
        case .free: .secondary.opacity(0.12)
        }
    }

    static func color(_ category: SafetyCategory) -> Color {
        switch category {
        case .safe: color(StorageBreakdown.Kind.safe)
        case .rebuild: color(StorageBreakdown.Kind.rebuild)
        case .risky: color(StorageBreakdown.Kind.risky)
        }
    }

    /// One line under each category card, saying what deleting means.
    static func footnote(_ category: SafetyCategory) -> String {
        switch category {
        case .safe: "Caches and leftovers that come back on their own when needed."
        case .rebuild: "Safe to remove, but the next use is slower while they rebuild or re-download."
        case .risky: "Your data or live state. Shown so you know where the space went — no commands."
        }
    }

    /// SF Symbol per target. All names checked to exist on this macOS.
    static func symbol(for targetID: String) -> String {
        switch targetID {
        case "hf-incomplete": "arrow.down.circle"
        case "aerials": "film"
        case "npm-cache", "yarn-cache", "npx-cache", "uv-cache": "shippingbox"
        case "chrome-model": "cpu"
        case "puppeteer", "headless-browsers": "globe"
        case "shipit": "arrow.triangle.2.circlepath"
        case "misc-build-caches", "node-gyp": "hammer"
        case "claude-vm": "server.rack"
        case "colima-cache": "externaldrive"
        case "electron": "atom"
        case "prisma": "cylinder"
        case "chrome-profile": "person.crop.circle"
        case "colima-vm": "cube"
        case "claude-sessions": "bubble.left.and.bubble.right"
        case "anki": "rectangle.stack"
        case "hf-models": "brain"
        default: "folder"
        }
    }
}

/// A row-sized rounded icon tile tinted with a category color.
struct IconTile: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// Grouped container, like an inset-grouped list section.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06))
            )
    }
}
