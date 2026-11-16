/// How the whole disk splits up, for the segmented usage bar.
/// Segments always add up to `totalBytes`.
public struct StorageBreakdown: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        case safe, rebuild, risky, other, free

        public var title: String {
            switch self {
            case .safe: "Safe to delete"
            case .rebuild: "Rebuilds"
            case .risky: "Keep"
            case .other: "Everything else"
            case .free: "Free"
            }
        }
    }

    public struct Segment: Hashable, Sendable {
        public let kind: Kind
        public let bytes: Int64
    }

    public let totalBytes: Int64
    public let segments: [Segment]

    public init(space: DiskSpace, results: [ScanResult]) {
        let total = max(0, space.totalBytes)
        let free = min(max(0, space.availableBytes), total)
        var remaining = total - free

        func categoryTotal(_ category: SafetyCategory) -> Int64 {
            results.filter { $0.exists && $0.target.category == category }.reduce(0) { $0 + $1.bytes }
        }
        // Take each category out of the used space in order; clamp so a
        // stale or over-counted total can never push the bar past 100%.
        var segments: [Segment] = []
        for (kind, category) in [(Kind.safe, SafetyCategory.safe), (.rebuild, .rebuild), (.risky, .risky)] {
            let bytes = min(categoryTotal(category), remaining)
            remaining -= bytes
            segments.append(Segment(kind: kind, bytes: bytes))
        }
        segments.append(Segment(kind: .other, bytes: remaining))
        segments.append(Segment(kind: .free, bytes: free))

        self.totalBytes = total
        self.segments = segments
    }

    public func bytes(_ kind: Kind) -> Int64 {
        segments.first { $0.kind == kind }?.bytes ?? 0
    }

    public func fraction(_ kind: Kind) -> Double {
        totalBytes > 0 ? Double(bytes(kind)) / Double(totalBytes) : 0
    }
}
