import Foundation

/// Checks the safety rules from PLAN.md §5.2 over a target list.
/// Returns human-readable violations; empty means the catalog is valid.
public enum CatalogValidator {
    public static func violations(in targets: [Target]) -> [String] {
        var problems: [String] = []

        // Unique ids.
        var seen = Set<String>()
        for target in targets where !seen.insert(target.id).inserted {
            problems.append("\(target.id): duplicate id")
        }

        for target in targets {
            problems += commandViolations(target)
        }
        problems += overlapViolations(targets)
        return problems
    }

    // MARK: - Commands

    private static func commandViolations(_ target: Target) -> [String] {
        let id = target.id
        switch (target.category, target.cleanup) {
        case (.risky, nil):
            return []
        case (.risky, .some):
            return ["\(id): risky target must not have a cleanup command"]
        case (_, nil):
            return ["\(id): safe/rebuild target needs a cleanup command"]
        case (_, .tool):
            return target.measure.usesExclusion
                ? ["\(id): a deletable target must not use .excluding"] : []
        case (_, .shell(let command)):
            var problems: [String] = []
            if target.measure.usesExclusion {
                // A command can't express "this folder minus that one".
                problems.append("\(id): a deletable target must not use .excluding")
            }
            let words = shellWords(command)
            let commandPaths = Set(words.filter(isPath).map(normalizeCommandPath))
            let leaves = target.measure.includedLeaves
            let measuredPaths = Set(leaves.compactMap(\.leafPath))

            for missing in measuredPaths.subtracting(commandPaths).sorted() {
                problems.append("\(id): command does not remove measured path \(missing)")
            }
            for extra in commandPaths.subtracting(measuredPaths).sorted() {
                problems.append("\(id): command removes unmeasured path \(extra)")
            }
            for case .files(_, let pattern) in leaves where !words.contains(pattern) {
                problems.append("\(id): command does not use measured pattern \(pattern)")
            }
            return problems
        }
    }

    private static func isPath(_ word: String) -> Bool {
        word.hasPrefix("~/") || word.hasPrefix("/")
    }

    /// `dir/*` removes the contents of `dir`, which is what measuring `dir` counts.
    private static func normalizeCommandPath(_ path: String) -> String {
        path.hasSuffix("/*") ? String(path.dropLast(2)) : path
    }

    // MARK: - Overlaps

    /// No bytes may be counted by two targets: if one target's leaf covers another
    /// target's leaf, the outer target must exclude it.
    private static func overlapViolations(_ targets: [Target]) -> [String] {
        var problems: [String] = []
        for outer in targets {
            for inner in targets where inner.id != outer.id {
                for a in outer.measure.includedLeaves {
                    for b in inner.measure.includedLeaves where covers(a, b) {
                        let excluded = outer.measure.excludedLeaves.contains { covers($0, b) }
                        if !excluded {
                            problems.append("\(outer.id) double-counts \(inner.id) (\(b.leafPath ?? "?"))")
                        }
                    }
                }
            }
        }
        return problems
    }

    /// Whether every byte measured by leaf `b` is also measured by leaf `a`.
    static func covers(_ a: Measure, _ b: Measure) -> Bool {
        if a == b { return true }
        // A pattern-filtered file set never fully contains another leaf.
        if case .files = a { return false }
        guard let pa = a.leafPath, let pb = b.leafPath else { return false }

        if case .glob(let pattern) = a {
            // Covered if any directory-boundary prefix of b's path matches the glob.
            let components = pb.split(separator: "/", omittingEmptySubsequences: false)
            return (1...components.count).contains { n in
                let prefix = components.prefix(n).joined(separator: "/")
                return fnmatch(pattern, prefix, FNM_PATHNAME) == 0
            }
        }
        return pb == pa || pb.hasPrefix(pa + "/")
    }

    // MARK: - Shell words

    /// Splits a command into words the way a POSIX shell would for quoting and
    /// backslash escapes (no expansion). Enough to read paths out of our commands.
    public static func shellWords(_ command: String) -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character? = nil
        var iterator = command.makeIterator()

        while let c = iterator.next() {
            if let q = quote {
                if c == q {
                    quote = nil
                } else if c == "\\" && q == "\"", let next = iterator.next() {
                    if !"\"\\$`".contains(next) { current.append("\\") }
                    current.append(next)
                } else {
                    current.append(c)
                }
            } else if c == "'" || c == "\"" {
                quote = c
                inWord = true
            } else if c == "\\" {
                if let next = iterator.next() { current.append(next) }
                inWord = true
            } else if c.isWhitespace {
                if inWord { words.append(current) }
                current = ""
                inWord = false
            } else {
                current.append(c)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}
