import Foundation
import StorageAnalysisCore

// Minimal check runner (see Package.swift for why this isn't `swift test`).
// Exits non-zero if any check fails.
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

func checkEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String, file: String = #fileID, line: Int = #line) {
    check(actual == expected, "\(name): expected \(expected), got \(actual)", file: file, line: line)
}

let KB: Int64 = 1024

// MARK: - SafetyCategory

check(SafetyCategory.safe.allowsCleanupCommand, "safe allows cleanup command")
check(SafetyCategory.rebuild.allowsCleanupCommand, "rebuild allows cleanup command")
check(!SafetyCategory.risky.allowsCleanupCommand, "risky forbids cleanup command")
check(SafetyCategory.allCases == [.safe, .rebuild, .risky], "categories ordered safe, rebuild, risky")

// MARK: - Parsing

checkEqual(Parsing.duTotalBytes("12\t/a\n34\t/b\n46\ttotal\n"), 46 * KB, "du total line")
checkEqual(Parsing.duTotalBytes("7\ttotal"), 7 * KB, "du single total line")
checkEqual(Parsing.duTotalBytes(""), nil, "du empty output")
checkEqual(Parsing.duTotalBytes("du: /x: Permission denied\n"), nil, "du garbage output")

let dfSample = """
Filesystem   1024-blocks      Used Available Capacity  Mounted on
/dev/disk3s5   239362496 202675924   9084856    96%    /System/Volumes/Data
"""
let df = Parsing.dfDiskSpace(dfSample)
checkEqual(df?.totalBytes, 239362496 * KB, "df total")
checkEqual(df?.usedBytes, 202675924 * KB, "df used")
checkEqual(df?.availableBytes, 9084856 * KB, "df available")
check(abs((df?.fractionUsed ?? 0) - 0.96204) < 0.0001, "df fraction used = (total - avail) / total")
checkEqual(Parsing.dfDiskSpace("Filesystem 1024-blocks\n"), nil, "df header only")

// MARK: - Shell words

checkEqual(
    CatalogValidator.shellWords(#"rm -rf ~/Library/Application\ Support/x/*"#),
    ["rm", "-rf", "~/Library/Application Support/x/*"],
    "shellWords backslash-escaped space"
)
checkEqual(
    CatalogValidator.shellWords(#"find ~/a -name "*.incomplete" -delete"#),
    ["find", "~/a", "-name", "*.incomplete", "-delete"],
    "shellWords double quotes"
)
checkEqual(CatalogValidator.shellWords("echo 'a b'  c"), ["echo", "a b", "c"], "shellWords single quotes")

// MARK: - Measures against a temp fixture

let fm = FileManager.default
let fixture = fm.temporaryDirectory.appendingPathComponent("storage-analysis-checks-\(UUID().uuidString)").path
defer { try? fm.removeItem(atPath: fixture) }

/// Writes `kilobytes` KB of non-zero bytes (a multiple of 4 KB fills APFS blocks exactly).
@MainActor func makeFile(_ relative: String, kilobytes: Int) {
    let path = "\(fixture)/\(relative)"
    try! fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    fm.createFile(atPath: path, contents: Data(repeating: 0xAB, count: kilobytes * 1024))
}

makeFile("dir/a.bin", kilobytes: 100)
makeFile("dir/b.bin", kilobytes: 100)
makeFile("dir/sub/c.bin", kilobytes: 100)
makeFile("hf/x.incomplete", kilobytes: 100)
makeFile("hf/y.bin", kilobytes: 200)
makeFile("hf/deep/z.incomplete", kilobytes: 40)
makeFile("caches/one.ShipIt/f", kilobytes: 100)
makeFile("caches/two.ShipIt/f", kilobytes: 100)
makeFile("caches/other/f", kilobytes: 100)

let scanner = Scanner()

/// du counts directory entries too, so allow a little slack above the file total.
@MainActor func checkRoughly(_ m: MeasuredSize, _ expectedKB: Int64, _ name: String, file: String = #fileID, line: Int = #line) {
    let ok = m.exists && m.bytes >= expectedKB * KB && m.bytes <= (expectedKB + 32) * KB && m.errors.isEmpty
    check(ok, "\(name): expected ~\(expectedKB) KB, got \(m.bytes / KB) KB exists=\(m.exists) errors=\(m.errors)", file: file, line: line)
}

checkRoughly(await scanner.measure(.directory("\(fixture)/dir")), 300, ".directory sums the tree")
checkEqual(await scanner.measure(.directory("\(fixture)/nope")), .missing, ".directory missing path")

let incomplete = await scanner.measure(.files(root: "\(fixture)/hf", pattern: "*.incomplete"))
checkEqual(incomplete, MeasuredSize(bytes: 140 * KB, exists: true, errors: []), ".files matches pattern recursively, exact allocated size")
checkEqual(await scanner.measure(.files(root: "\(fixture)/hf", pattern: "*.nothing")), .missing, ".files no matches")
checkEqual(await scanner.measure(.files(root: "\(fixture)/nope", pattern: "*")), .missing, ".files missing root")

checkRoughly(await scanner.measure(.glob("\(fixture)/caches/*.ShipIt")), 200, ".glob sums every match only")
checkEqual(await scanner.measure(.glob("\(fixture)/caches/*.nothing")), .missing, ".glob no matches")

checkRoughly(
    await scanner.measure(.sum([.directory("\(fixture)/caches/other"), .directory("\(fixture)/nope")])),
    100, ".sum skips missing parts"
)
checkEqual(
    await scanner.measure(.sum([.directory("\(fixture)/nope"), .glob("\(fixture)/nope/*")])),
    .missing, ".sum of all-missing is missing"
)

let dirMinusSub = await scanner.measure(.excluding(.directory("\(fixture)/dir"), minus: [.directory("\(fixture)/dir/sub")]))
check(dirMinusSub.exists && dirMinusSub.bytes >= 190 * KB && dirMinusSub.bytes <= 232 * KB,
      ".excluding subtracts the inner part: got \(dirMinusSub.bytes / KB) KB")
let hfMinusIncomplete = await scanner.measure(.excluding(.directory("\(fixture)/hf"), minus: [.files(root: "\(fixture)/hf", pattern: "*.incomplete")]))
check(hfMinusIncomplete.bytes >= 200 * KB && hfMinusIncomplete.bytes <= 232 * KB,
      ".excluding with a pattern: got \(hfMinusIncomplete.bytes / KB) KB")
checkEqual(
    await scanner.measure(.excluding(.directory("\(fixture)/nope"), minus: [.directory("\(fixture)/dir")])),
    .missing, ".excluding missing base"
)
checkEqual(
    await scanner.measure(.excluding(.directory("\(fixture)/caches/other"), minus: [.directory("\(fixture)/dir")])).bytes,
    0, ".excluding clamps at zero"
)

// MARK: - Scanner.scan

let fixtureTargets = [
    Target(id: "a", name: "A", measure: .directory("\(fixture)/dir"), purpose: "", category: .safe, cleanup: .tool("x")),
    Target(id: "b", name: "B", measure: .directory("\(fixture)/nope"), purpose: "", category: .risky, cleanup: nil),
]
final class ProgressLog: @unchecked Sendable { var ticks: [String] = [] }
let progressLog = ProgressLog()
let results = await scanner.scan(fixtureTargets) { done, total in progressLog.ticks.append("\(done)/\(total)") }
checkEqual(results.map(\.target.id), ["a", "b"], "scan keeps target order")
checkEqual(results.map(\.exists), [true, false], "scan reports existence")
checkEqual(progressLog.ticks, ["1/2", "2/2"], "scan reports progress per target")

// MARK: - Catalog rules (PLAN.md §5.2)

let catalogProblems = CatalogValidator.violations(in: TargetCatalog.all)
check(catalogProblems.isEmpty, "real catalog is valid:\n  " + catalogProblems.joined(separator: "\n  "))
checkEqual(TargetCatalog.all.count, 21, "catalog has the 21 Appendix A targets")
checkEqual(TargetCatalog.all.filter { $0.category == .risky }.count, 5, "5 risky targets")

// The validator must actually catch each kind of mistake.
func violations(_ targets: [Target]) -> [String] { CatalogValidator.violations(in: targets) }
func t(_ id: String, _ measure: Measure, _ category: SafetyCategory, _ cleanup: Cleanup?) -> Target {
    Target(id: id, name: id, measure: measure, purpose: "", category: category, cleanup: cleanup)
}

check(!violations([t("r", .directory("~/x"), .risky, .shell("rm -rf ~/x"))]).isEmpty, "rejects risky with command")
check(!violations([t("s", .directory("~/x"), .safe, nil)]).isEmpty, "rejects safe without command")
check(!violations([t("s", .sum([.directory("~/x"), .directory("~/y")]), .safe, .shell("rm -rf ~/x"))]).isEmpty,
      "rejects command missing a measured path")
check(!violations([t("s", .directory("~/x"), .safe, .shell("rm -rf ~/x ~/y"))]).isEmpty,
      "rejects command removing an unmeasured path")
check(!violations([t("s", .files(root: "~/x", pattern: "*.a"), .safe, .shell("find ~/x -name '*.b' -delete"))]).isEmpty,
      "rejects command with the wrong pattern")
check(!violations([t("s", .excluding(.directory("~/x"), minus: [.directory("~/x/y")]), .safe, .shell("rm -rf ~/x"))]).isEmpty,
      "rejects deletable target using .excluding")
check(!violations([t("a", .directory("~/x"), .safe, .tool("t")), t("a", .directory("~/y"), .safe, .tool("t"))]).isEmpty,
      "rejects duplicate ids")
check(!violations([t("outer", .directory("~/x"), .risky, nil), t("inner", .directory("~/x/y"), .safe, .tool("t"))]).isEmpty,
      "rejects nested directory without exclusion")
check(!violations([t("outer", .directory("~/c"), .risky, nil), t("inner", .glob("~/c/*.S"), .safe, .tool("t"))]).isEmpty,
      "rejects directory containing a glob without exclusion")
check(!violations([t("g", .glob("~/c/*.S"), .safe, .tool("t")), t("d", .directory("~/c/a.S/z"), .risky, nil)]).isEmpty,
      "rejects glob containing a directory without exclusion")
check(violations([t("outer", .excluding(.directory("~/x"), minus: [.directory("~/x/y")]), .risky, nil),
                  t("inner", .directory("~/x/y"), .safe, .tool("t"))]).isEmpty,
      "accepts nested directory with exclusion")
check(violations([t("a", .directory("~/xy"), .safe, .tool("t")), t("b", .directory("~/x"), .safe, .tool("t"))]).isEmpty,
      "sibling prefix (~/x vs ~/xy) is not an overlap")

// MARK: - Format

checkEqual(Format.compact(9_260_000_000), "9.3 GB", "compact GB one decimal")
checkEqual(Format.compact(245_110_000_000), "245 GB", "compact >= 100 drops decimal")
checkEqual(Format.compact(850_000_000), "850 MB", "compact MB")
checkEqual(Format.compact(999), "999 B", "compact bytes")
checkEqual(Format.compact(-5), "0 B", "compact clamps negatives")
let nearlyFull = DiskSpace(totalBytes: 100_000_000_000, usedBytes: 80_000_000_000, availableBytes: 5_000_000_000)
let roomy = DiskSpace(totalBytes: 100_000_000_000, usedBytes: 50_000_000_000, availableBytes: 50_000_000_000)
checkEqual(Format.menuBarLabel(nearlyFull), "⚠︎ 5.0 GB", "label warns at >= 90% used")
checkEqual(Format.menuBarLabel(roomy), "50.0 GB", "label plain below 90%")
checkEqual(Format.spaceSummary(nearlyFull), "5.0 GB free of 100 GB · 95% used", "space summary")

// MARK: - Reveal path

checkEqual(Scanner.revealPath(for: .directory("\(fixture)/dir")), "\(fixture)/dir", "reveal directory")
checkEqual(Scanner.revealPath(for: .directory("\(fixture)/nope")), nil, "reveal missing")
checkEqual(Scanner.revealPath(for: .sum([.directory("\(fixture)/nope"), .directory("\(fixture)/hf")])), "\(fixture)/hf", "reveal first existing in sum")
checkEqual(Scanner.revealPath(for: .glob("\(fixture)/caches/*.ShipIt")), "\(fixture)/caches/one.ShipIt", "reveal first glob match")
checkEqual(Scanner.revealPath(for: .excluding(.directory("\(fixture)/dir"), minus: [])), "\(fixture)/dir", "reveal excluding base")

print("\(passed) passed, \(failures) failed")
if failures > 0 { exit(1) }
