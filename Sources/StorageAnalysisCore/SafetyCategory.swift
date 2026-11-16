/// Safety category for a scanned target (PLAN.md §5.2, §5.4).
public enum SafetyCategory: String, CaseIterable, Sendable {
    case safe
    case rebuild
    case risky

    public var title: String {
        switch self {
        case .safe: "Safe to delete"
        case .rebuild: "Safe but rebuilds"
        case .risky: "Risky / avoid"
        }
    }

    public var symbol: String {
        switch self {
        case .safe: "🟢"
        case .rebuild: "🟡"
        case .risky: "🔴"
        }
    }

    /// Risky items never get a cleanup command or copy button.
    public var allowsCleanupCommand: Bool { self != .risky }
}
