import Foundation

/// One big file found inside the scanned targets.
public struct LargeFile: Hashable, Sendable, Identifiable {
    public let path: String
    public let bytes: Int64
    /// The target whose row counts this file (nil only if no target claims it).
    public let owner: Target?

    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }

    /// Parent folder with the home directory shortened to `~`.
    public var displayFolder: String {
        let folder = (path as NSString).deletingLastPathComponent
        let home = NSHomeDirectory()
        return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
    }
}

public struct LargeFileReport: Hashable, Sendable {
    public let files: [LargeFile]
    /// Folders or files that couldn't be read while searching.
    public let unreadableCount: Int
}

extension Measure {
    /// Whether this measure counts the file at `path` (an absolute, expanded path).
    public func contains(path: String) -> Bool {
        switch self {
        case .directory(let dir):
            let dir = Scanner.expand(dir)
            return path == dir || path.hasPrefix(dir + "/")
        case .files(let root, let pattern):
            let root = Scanner.expand(root)
            return path.hasPrefix(root + "/")
                && fnmatch(pattern, (path as NSString).lastPathComponent, 0) == 0
        case .glob(let pattern):
            let pattern = Scanner.expand(pattern)
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            return (1...components.count).contains { n in
                fnmatch(pattern, components.prefix(n).joined(separator: "/"), FNM_PATHNAME) == 0
            }
        case .sum(let parts):
            return parts.contains { $0.contains(path: path) }
        case .excluding(let base, let minus):
            return base.contains(path: path) && !minus.contains { $0.contains(path: path) }
        }
    }
}

extension Scanner {
    /// The largest files inside the targets' folders — never outside them
    /// (PLAN.md: no whole-disk crawl). Read-only.
    public func largestFiles(
        in targets: [Target],
        minimumBytes: Int64 = 100 * 1024 * 1024,
        limit: Int = 10
    ) async -> LargeFileReport {
        await offCooperativePool {
            Self.findLargestFiles(in: targets, minimumBytes: minimumBytes, limit: limit)
        }
    }

    /// Existing folders to walk: every target leaf, with nested ones dropped so
    /// nothing is walked twice.
    public static func searchRoots(for targets: [Target]) -> [String] {
        var roots: [String] = []
        for leaf in targets.flatMap(\.measure.includedLeaves) {
            switch leaf {
            case .directory(let path): roots.append(expand(path))
            case .files(let root, _): roots.append(expand(root))
            case .glob(let pattern): roots += expandGlob(expand(pattern))
            case .sum, .excluding: break
            }
        }
        let existing = Set(roots).filter { FileManager.default.fileExists(atPath: $0) }
        return existing
            .filter { root in !existing.contains { other in other != root && root.hasPrefix(other + "/") } }
            .sorted()
    }

    static func underRoot(_ path: String, root: String, resolvedRoot: String) -> String {
        if path == resolvedRoot { return root }
        if path.hasPrefix(resolvedRoot + "/") { return root + path.dropFirst(resolvedRoot.count) }
        return path
    }

    private static func findLargestFiles(in targets: [Target], minimumBytes: Int64, limit: Int) -> LargeFileReport {
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        var found: [(path: String, bytes: Int64)] = []
        var unreadable = 0

        for root in searchRoots(for: targets) {
            let rootURL = URL(fileURLWithPath: root)
            // The enumerator reports symlink-resolved paths (e.g. /private/var/…
            // for /var/…); map them back so they match the targets' paths.
            let resolvedRoot = realpath(root, nil).map { p in defer { free(p) }; return String(cString: p) } ?? root
            // A root can itself be a file (e.g. a glob match).
            let candidates: AnySequence<URL>
            if let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: { _, _ in unreadable += 1; return true }
            ) {
                candidates = AnySequence(enumerator.lazy.compactMap { $0 as? URL } + [rootURL])
            } else {
                candidates = AnySequence([rootURL])
            }

            for url in candidates {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let size = values.totalFileAllocatedSize,
                      Int64(size) >= minimumBytes
                else { continue }
                found.append((Self.underRoot(url.path, root: root, resolvedRoot: resolvedRoot), Int64(size)))
            }
        }

        let top = found.sorted { $0.bytes > $1.bytes }.prefix(limit)
        let files = top.map { item in
            LargeFile(
                path: item.path,
                bytes: item.bytes,
                owner: targets.first { $0.measure.contains(path: item.path) }
            )
        }
        return LargeFileReport(files: files, unreadableCount: unreadable)
    }
}
