import Foundation

/// Display formatting. Sizes use decimal units (1 GB = 10⁹ bytes), like Finder.
public enum Format {
    /// "9.3 GB", "12 GB", "850 MB". One decimal below 100 of a unit.
    public static func compact(_ bytes: Int64) -> String {
        let units: [(String, Double)] = [("TB", 1e12), ("GB", 1e9), ("MB", 1e6), ("KB", 1e3)]
        let value = Double(max(0, bytes))
        for (name, size) in units where value >= size {
            let scaled = value / size
            return scaled < 100
                ? String(format: "%.1f %@", scaled, name)
                : String(format: "%.0f %@", scaled, name)
        }
        return "\(max(0, bytes)) B"
    }

    /// At or above this share used, the menu bar shows a warning symbol.
    public static let warningFraction = 0.9

    /// Menu-bar label: free space plus an SF Symbol name — a warning triangle
    /// when the disk is at least 90% used, a drive otherwise.
    public static func menuBarLabel(_ space: DiskSpace) -> (text: String, symbol: String) {
        let warning = space.fractionUsed >= warningFraction
        return (compact(space.availableBytes), warning ? "exclamationmark.triangle.fill" : "internaldrive")
    }

    /// "9.3 GB free of 245 GB · 96% used"
    public static func spaceSummary(_ space: DiskSpace) -> String {
        "\(compact(space.availableBytes)) free of \(compact(space.totalBytes)) · \(percent(space.fractionUsed)) used"
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

extension Scanner {
    /// The path to show in Finder for a measure: the first existing directory,
    /// glob match, or pattern root. `nil` when nothing exists.
    public static func revealPath(for measure: Measure) -> String? {
        let fm = FileManager.default
        switch measure {
        case .directory(let path):
            let path = expand(path)
            return fm.fileExists(atPath: path) ? path : nil
        case .files(let root, _):
            let root = expand(root)
            return fm.fileExists(atPath: root) ? root : nil
        case .glob(let pattern):
            return expandGlob(expand(pattern)).first
        case .sum(let parts):
            return parts.lazy.compactMap(revealPath(for:)).first
        case .excluding(let base, _):
            return revealPath(for: base)
        }
    }
}
