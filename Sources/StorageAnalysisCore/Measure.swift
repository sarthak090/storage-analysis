/// How a target's size is measured (PLAN.md §5.2).
/// Paths may start with `~/`; they are expanded at scan time.
public indirect enum Measure: Hashable, Sendable {
    /// One directory: `du -sk <path>`.
    case directory(String)
    /// Regular files under `root` whose name matches `pattern` (e.g. "*.incomplete").
    case files(root: String, pattern: String)
    /// Every path matching a glob (e.g. "~/Library/Caches/*.ShipIt"), via glob(3).
    case glob(String)
    /// Several measures shown as one row.
    case sum([Measure])
    /// A measure minus parts that are reported as their own rows.
    case excluding(Measure, minus: [Measure])

    /// The leaf measures (directory / files / glob) counted toward the total.
    public var includedLeaves: [Measure] {
        switch self {
        case .directory, .files, .glob: [self]
        case .sum(let parts): parts.flatMap(\.includedLeaves)
        case .excluding(let base, _): base.includedLeaves
        }
    }

    /// The leaf measures subtracted from the total.
    public var excludedLeaves: [Measure] {
        switch self {
        case .directory, .files, .glob: []
        case .sum(let parts): parts.flatMap(\.excludedLeaves)
        case .excluding(let base, let minus): base.excludedLeaves + minus.flatMap(\.includedLeaves)
        }
    }

    public var usesExclusion: Bool { !excludedLeaves.isEmpty }

    /// The path a leaf refers to: the directory, the files' root, or the glob pattern.
    /// `nil` for `.sum` / `.excluding`.
    public var leafPath: String? {
        switch self {
        case .directory(let path): path
        case .files(let root, _): root
        case .glob(let pattern): pattern
        case .sum, .excluding: nil
        }
    }
}
