import StorageAnalysisCore
import Foundation

// Minimal check runner. Exits non-zero if any check fails.
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passed = 0

func check(_ condition: Bool, _ name: String, file: String = #fileID, line: Int = #line) {
    if condition {
        passed += 1
    } else {
        failures += 1
        print("FAIL \(name) (\(file):\(line))")
    }
}

// MARK: SafetyCategory
check(SafetyCategory.safe.allowsCleanupCommand, "safe allows cleanup command")
check(SafetyCategory.rebuild.allowsCleanupCommand, "rebuild allows cleanup command")
check(!SafetyCategory.risky.allowsCleanupCommand, "risky forbids cleanup command")
check(SafetyCategory.allCases == [.safe, .rebuild, .risky], "categories ordered safe, rebuild, risky")

print("\(passed) passed, \(failures) failed")
if failures > 0 { exit(1) }
