/// Free space on the data volume.
public struct DiskSpace: Hashable, Sendable {
    public let totalBytes: Int64
    public let usedBytes: Int64
    public let availableBytes: Int64

    /// Share of the whole disk not available to you: `(total - available) / total`.
    /// This counts the system, VM and other APFS volumes sharing the container,
    /// which is what "my disk is full" means. (df's own Capacity column only
    /// counts this volume's `used`, so it reads slightly lower.)
    public var fractionUsed: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(totalBytes - availableBytes) / Double(totalBytes)
    }

    public init(totalBytes: Int64, usedBytes: Int64, availableBytes: Int64) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.availableBytes = availableBytes
    }
}

public enum Parsing {
    /// Parses `du -skc ...` output: the last line is `<kilobytes>\ttotal`.
    public static func duTotalBytes(_ output: String) -> Int64? {
        guard let last = output.split(whereSeparator: \.isNewline).last,
              let field = last.split(whereSeparator: \.isWhitespace).first,
              let kilobytes = Int64(field)
        else { return nil }
        return kilobytes * 1024
    }

    /// Parses `df -kP <volume>` output:
    /// `Filesystem 1024-blocks Used Available Capacity Mounted on`, then one data line.
    public static func dfDiskSpace(_ output: String) -> DiskSpace? {
        let lines = output.split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else { return nil }
        let fields = lines[1].split(whereSeparator: \.isWhitespace)
        guard fields.count >= 4,
              let total = Int64(fields[1]),
              let used = Int64(fields[2]),
              let available = Int64(fields[3])
        else { return nil }
        return DiskSpace(totalBytes: total * 1024, usedBytes: used * 1024, availableBytes: available * 1024)
    }
}
