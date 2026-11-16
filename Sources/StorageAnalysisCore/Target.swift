/// A cleanup command the user can copy. The app never runs it.
public enum Cleanup: Hashable, Sendable {
    /// A shell command that names the paths it removes. Validated: it must name
    /// exactly the paths the target measures (see `CatalogValidator`).
    case shell(String)
    /// A tool's own cleanup command (e.g. `npm cache clean --force`), which
    /// manages the measured directory itself. Path check doesn't apply.
    case tool(String)

    public var command: String {
        switch self {
        case .shell(let command), .tool(let command): command
        }
    }
}

/// A curated scan target (PLAN.md §5.2, Appendix A).
public struct Target: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let measure: Measure
    public let purpose: String
    public let category: SafetyCategory
    public let cleanup: Cleanup?
    /// Extra guidance, e.g. the safe alternative for a risky item.
    public let note: String?

    public init(
        id: String,
        name: String,
        measure: Measure,
        purpose: String,
        category: SafetyCategory,
        cleanup: Cleanup?,
        note: String? = nil
    ) {
        self.id = id
        self.name = name
        self.measure = measure
        self.purpose = purpose
        self.category = category
        self.cleanup = cleanup
        self.note = note
    }
}

/// The outcome of measuring one target.
public struct ScanResult: Hashable, Sendable, Identifiable {
    public let target: Target
    public let bytes: Int64
    /// False when nothing matched (path missing, glob/pattern matched nothing).
    public let exists: Bool
    /// Problems hit while measuring (e.g. permission denied on part of the tree).
    /// The size may be an undercount when this is non-empty.
    public let errors: [String]

    public var id: String { target.id }

    public init(target: Target, bytes: Int64, exists: Bool, errors: [String]) {
        self.target = target
        self.bytes = bytes
        self.exists = exists
        self.errors = errors
    }
}
