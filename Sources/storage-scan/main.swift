import Foundation
import StorageAnalysisCore

// Debug tool: runs the real scan and prints it. `swift run storage-scan`
// Read-only, like the app.

let scanner = Scanner()
func size(_ bytes: Int64) -> String {
    ProcessInfo.processInfo.arguments.contains("--kb") ? "\(bytes / 1024) KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

do {
    let space = try await scanner.diskSpace()
    print("Free: \(size(space.availableBytes)) of \(size(space.totalBytes)) · \(Int((space.fractionUsed * 100).rounded()))% used\n")
} catch {
    print("Free space: \(error)\n")
}

let start = Date()
let results = await scanner.scan(TargetCatalog.all)
for category in SafetyCategory.allCases {
    print("\(category.symbol) \(category.title)")
    for r in results.filter({ $0.target.category == category }).sorted(by: { $0.bytes > $1.bytes }) {
        let shown = r.exists ? size(r.bytes) : "—"
        let warn = r.errors.isEmpty ? "" : "  ⚠︎ \(r.errors.count) error(s): \(r.errors.first!)"
        print("  \(shown.padding(toLength: 12, withPad: " ", startingAt: 0)) \(r.target.name)\(warn)")
    }
    print()
}
print(String(format: "Scanned %d targets in %.1fs", results.count, Date().timeIntervalSince(start)))
