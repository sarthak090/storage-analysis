import Foundation

/// The size of one measure.
public struct MeasuredSize: Hashable, Sendable {
    public var bytes: Int64
    public var exists: Bool
    public var errors: [String]

    public static let missing = MeasuredSize(bytes: 0, exists: false, errors: [])

    public init(bytes: Int64, exists: Bool, errors: [String]) {
        self.bytes = bytes
        self.exists = exists
        self.errors = errors
    }
}

public enum ScanError: Error, CustomStringConvertible {
    case commandFailed(String)

    public var description: String {
        switch self {
        case .commandFailed(let message): message
        }
    }
}

/// Measures targets. Read-only: runs `du` / `df` and enumerates files; never deletes.
public struct Scanner: Sendable {
    /// The real data volume. Not `/`, which is the sealed read-only system snapshot.
    public static let dataVolume = "/System/Volumes/Data"

    public init() {}

    /// Measures every target in order, reporting `(finished, total)` after each.
    public func scan(
        _ targets: [Target],
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> [ScanResult] {
        var results: [ScanResult] = []
        results.reserveCapacity(targets.count)
        for (index, target) in targets.enumerated() {
            let m = await measure(target.measure)
            results.append(ScanResult(target: target, bytes: m.bytes, exists: m.exists, errors: m.errors))
            progress(index + 1, targets.count)
        }
        return results
    }

    public func diskSpace(volume: String = Scanner.dataVolume) async throws -> DiskSpace {
        let output = try await CommandRunner.run("/bin/df", ["-kP", volume])
        guard output.status == 0, let space = Parsing.dfDiskSpace(output.stdout) else {
            throw ScanError.commandFailed("df failed: \(output.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return space
    }

    public func measure(_ measure: Measure) async -> MeasuredSize {
        switch measure {
        case .directory(let path):
            return await du([Self.expand(path)])

        case .glob(let pattern):
            return await du(Self.expandGlob(Self.expand(pattern)))

        case .files(let root, let pattern):
            let root = Self.expand(root)
            return await offCooperativePool { Self.sumMatchingFiles(root: root, pattern: pattern) }

        case .sum(let parts):
            var total = MeasuredSize.missing
            for part in parts {
                let m = await self.measure(part)
                total.bytes += m.bytes
                total.exists = total.exists || m.exists
                total.errors += m.errors
            }
            return total

        case .excluding(let base, let minus):
            var result = await self.measure(base)
            guard result.exists else { return result }
            for part in minus {
                let m = await self.measure(part)
                result.bytes -= m.bytes
                result.errors += m.errors
            }
            result.bytes = max(0, result.bytes)
            return result
        }
    }

    // MARK: - Leaves

    /// `du -skc` over the paths that exist. Hard links are counted once.
    private func du(_ paths: [String]) async -> MeasuredSize {
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return .missing }

        let output: CommandOutput
        do {
            output = try await CommandRunner.run("/usr/bin/du", ["-skc", "--"] + existing)
        } catch {
            return MeasuredSize(bytes: 0, exists: true, errors: ["du could not run: \(error)"])
        }

        // du exits non-zero when part of a tree is unreadable but still prints a
        // total, so keep the number and record the problem.
        var errors: [String] = []
        if output.status != 0 {
            let lines = output.stderr.split(whereSeparator: \.isNewline).map(String.init)
            errors = Array(lines.prefix(3))
            if lines.count > 3 { errors.append("… and \(lines.count - 3) more") }
        }
        guard let bytes = Parsing.duTotalBytes(output.stdout) else {
            return MeasuredSize(bytes: 0, exists: true, errors: errors + ["could not parse du output"])
        }
        return MeasuredSize(bytes: bytes, exists: true, errors: errors)
    }

    private static func sumMatchingFiles(root: String, pattern: String) -> MeasuredSize {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .missing
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        let errorBox = ErrorBox()
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { url, error in
                errorBox.errors.append("\(url.path): \(error.localizedDescription)")
                return true // keep going
            }
        ) else {
            return MeasuredSize(bytes: 0, exists: true, errors: ["cannot enumerate \(root)"])
        }

        var bytes: Int64 = 0
        var matched = false
        for case let url as URL in enumerator {
            guard fnmatch(pattern, url.lastPathComponent, 0) == 0,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true
            else { continue }
            matched = true
            bytes += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return MeasuredSize(bytes: bytes, exists: matched, errors: Array(errorBox.errors.prefix(3)))
    }

    // MARK: - Paths

    static func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    static func expandGlob(_ pattern: String) -> [String] {
        var g = glob_t()
        defer { globfree(&g) }
        guard glob(pattern, 0, nil, &g) == 0 else { return [] }
        return (0..<Int(g.gl_pathc)).compactMap { i in
            g.gl_pathv[i].map { String(cString: $0) }
        }
    }
}

/// Only touched synchronously from the enumerator's error handler on one thread.
private final class ErrorBox: @unchecked Sendable {
    var errors: [String] = []
}
