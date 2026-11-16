import Foundation
import Observation
import StorageAnalysisCore

/// UI state for one scan at a time. Scans only when asked (launch or Rescan).
@MainActor
@Observable
final class ScanModel {
    private(set) var diskSpace: DiskSpace?
    private(set) var results: [ScanResult] = []
    private(set) var isScanning = false
    private(set) var progress: (done: Int, total: Int) = (0, 0)
    private(set) var lastScanned: Date?
    private(set) var diskSpaceError: String?
    private(set) var largeFiles: LargeFileReport?

    private let scanner = Scanner()
    private let targets: [Target]

    init(targets: [Target] = TargetCatalog.all) {
        self.targets = targets
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        progress = (0, targets.count)
        defer { isScanning = false }

        do {
            diskSpace = try await scanner.diskSpace()
            diskSpaceError = nil
        } catch {
            diskSpaceError = "\(error)"
        }

        // The large-file search walks the same folders; run it alongside.
        async let large = scanner.largestFiles(in: targets)
        results = await scanner.scan(targets) { done, total in
            Task { @MainActor [weak self] in self?.progress = (done, total) }
        }
        largeFiles = await large
        lastScanned = Date()
    }

    /// Found rows in a category, largest first. Rows with nothing on disk are hidden.
    func rows(in category: SafetyCategory) -> [ScanResult] {
        results
            .filter { $0.target.category == category && $0.exists }
            .sorted { $0.bytes > $1.bytes }
    }

    func total(in category: SafetyCategory) -> Int64 {
        rows(in: category).reduce(0) { $0 + $1.bytes }
    }

    var menuBarLabel: String {
        diskSpace.map(Format.menuBarLabel) ?? "Storage…"
    }
}
