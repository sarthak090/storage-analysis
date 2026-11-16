# Storage Analysis — Design & Plan

**Date:** 2026-11-06 (revised 2026-11-16)
**Author:** Sarthak (with Claude Code)
**Status:** Approved 2026-11-16 — Phases 1–5 done
**Location:** `~/Desktop/experiments/storage-analysis/`

---

## 1. Intent & Why

macOS accumulates many gigabytes of developer and app caches, package-manager
stores, VM disk images, stale app-update staging dirs, and failed downloads.
These are scattered across non-obvious paths (`~/Library/Caches`,
`~/Library/Application Support`, `~/.npm`, `~/.cache`, `~/.colima`, etc.) and
Finder gives no useful view of them. A one-off terminal scan works but isn't
repeatable or glanceable.

**The idea:** a lightweight macOS **menu-bar app** that scans the known
cache/storage-heavy locations on demand, shows a ranked, categorized breakdown
in a popover, and surfaces **copy-ready cleanup commands** — without ever
deleting anything itself.

**Why now:** The data volume was **94% full (≈14 GB free of 228 GB)** on
2026-11-06, and is **97% full (≈7.7 GB free)** on 2026-11-16 — even though
several caches (uv, puppeteer, Playwright, go-build, HuggingFace partial
downloads, ShipIt leftovers) were cleaned in between. Space fills back up within
days, so a glanceable, repeatable tool beats re-running an ad-hoc scan each time.

**Grounded in real scans** (2026-11-06 and 2026-11-16) — the categorization
rules and target list in this plan are derived from measured data on this
machine, not guesses. See Appendix A. The appendix figures are a snapshot for
sizing the problem; the app always shows live numbers.

---

## 2. Goals / Non-Goals / Anti-Goals

### Goals
- One-click (menu-bar) scan of a curated set of storage-heavy directories.
- Show: largest folders, largest files, estimated size, free-space summary,
  a plain-English "what it is", and a safety category per item.
- Categorize every finding into: **Safe to delete**, **Safe but rebuilds**,
  **Risky / avoid**.
- For each safe item, provide a **copy-to-clipboard cleanup command**.
- Native, glanceable SwiftUI `MenuBarExtra` UI.

### Non-Goals
- No scheduled/background scanning (manual trigger only, at least v1).
- No full-disk / whole-filesystem crawl — only the curated target list.
- No App Store distribution, notarization, or multi-user support.
- No cloud, telemetry, or network access of any kind.

### Anti-Goals (would make this a failure even if it "works")
- **Deleting anything automatically.** The app must never remove files. This is
  the hard line — report-only. (Reinforces the user's stated requirement.)
- Misclassifying real user data (e.g. an Anki database, a browser profile,
  live container volumes) as "safe to delete."
- Being heavier on disk than the junk it helps find (rules out an Electron
  bundle; native Swift keeps the footprint tiny).

---

## 3. Constraints

- **Platform:** macOS 26 (Darwin 25.5.0), Apple Silicon. SwiftUI `MenuBarExtra`
  requires macOS 13+ — fine.
- **Report-only:** no deletion code paths at all in v1. The app shells out only
  to *read* sizes (`du`, `df`, `find`) — never to `rm`.
- **No elevated privileges:** scan only paths readable as the current user
  (everything in the target list is under `~`).
- **Sandboxing:** a sandboxed app can't freely read arbitrary `~/Library`
  paths. v1 runs **non-sandboxed** (personal/dev build, run locally, no
  signing). Document this; revisit if distribution is ever wanted.
- **Performance:** `du` on 15–35 GB trees takes seconds. Scanning must run off
  the main thread so the UI never blocks; show a spinner/progress.

---

## 4. Approaches Considered

| Approach | Summary | Why / Why not |
|---|---|---|
| Python + `rumps` | Quick menu-bar app, reuse shell scan logic | Fastest, but dropdown-only UI can't render the rich popover; chosen against. |
| **Swift + SwiftUI `MenuBarExtra`** ✅ | Native menu-bar app with a real popover UI | **Chosen.** Best native feel, rich grouped/progress UI matching the mockup, tiny footprint, no extra toolchain to maintain. |
| Tauri (Rust + HTML popover) | Rich HTML popover, small binary | Rich UI + small, but adds a Rust/Tauri toolchain for an experiment; chosen against. |

**Decision:** Swift + SwiftUI `MenuBarExtra` (user's call, 2026-11-06).
Cleanup interaction: **report-only** (user's call) — the app displays and
copies cleanup commands but performs no deletion.

---

## 5. How It Works (the decided design)

### 5.1 Architecture
```
StorageAnalysisApp (SwiftUI App, MenuBarExtra "window" style)
├── Scanner            — evaluates each Target's Measure via du/find on a background task
│   └── produces [ScanResult]  (async; progress reported back to UI)
├── Targets            — the curated target list + metadata (purpose, category, command)
├── Classifier         — maps each target to a Category + "what it is" + cleanup command
└── Views
    ├── MenuBarExtra label  — free space in GB (e.g. "⚠︎ 7.7 GB"), see §5.5
    └── PopoverView         — header (free space), ranked list grouped by category,
                               per-row size + purpose + [Copy cleanup] button,
                               "Rescan" button, "Reveal in Finder" per row
```

### 5.2 Data model
A target is not always a single directory. The curated list needs four shapes,
so how a target is measured is its own type:

```swift
enum SafetyCategory { case safe, rebuild, risky }   // not `Category`: clashes with ObjC's typealias

indirect enum Measure {
    /// One directory: `du -sk <path>`.
    case directory(String)
    /// Files under `root` whose name matches `pattern` (e.g. "*.incomplete"):
    /// enumerate with FileManager, sum allocated sizes.
    case files(root: String, pattern: String)
    /// Every directory matching a path glob (e.g. "~/Library/Caches/*.ShipIt"),
    /// expanded with glob(3) — never through a shell — then `du -sk` each.
    case glob(String)
    /// Several measures shown as one row (e.g. ms-playwright + node-chromium).
    case sum([Measure])
    /// A measure minus parts reported as their own rows
    /// (e.g. Chrome profile minus OptGuideOnDeviceModel).
    case excluding(Measure, minus: [Measure])
}

struct Target {           // static, curated
    let id: String
    let name: String      // row title
    let measure: Measure  // paths are ~-expanded at scan time
    let purpose: String   // plain-English "what it is"
    let category: SafetyCategory
    let cleanup: Cleanup?         // nil for risky items
}

// The app's code also has: `Cleanup` (.shell = names its paths, validated;
// .tool = e.g. `npm cache clean`), a `note` per target, and `MeasuredSize`
// (not `Measurement`, which clashes with Foundation).

struct ScanResult {       // produced per scan
    let target: Target
    let bytes: Int64      // clamped to ≥ 0 for .excluding
    let exists: Bool      // false when nothing matched
    let errors: [String] // e.g. permission denied on part of the tree
}
```

**Invariants (enforced by unit tests):**
- `category == .risky` ⇔ `cleanupCommand == nil`.
- **The command deletes exactly what the row measures.** Every path or pattern
  in a safe/rebuild target's `measure` appears in its `cleanupCommand`, and the
  command names no path the measure doesn't cover. One row, one scope.
- **No double counting.** When one target's path contains another target's path
  (Chrome profile ⊃ Chrome model, HuggingFace ⊃ `*.incomplete`), the outer
  target must use `.excluding` to subtract the inner one. Test: no two targets
  measure overlapping bytes.

### 5.3 Scanning
- Enumerate the curated `Target` list (Appendix A) and evaluate each `Measure`:
  - `.directory` → `du -sk <path>` via `Process` (arguments array, no shell).
  - `.files` → `FileManager.enumerator`, match names with `fnmatch`, sum
    `totalFileAllocatedSize`.
  - `.glob` → `glob(3)` to expand, then `du -sk` each match.
  - `.sum` / `.excluding` → combine child results; `.excluding` clamps at 0.
- Missing paths are not errors: the row reports `exists == false` and is hidden
  (or greyed under "Nothing found") rather than shown as 0 B.
- Free space: `df -k /System/Volumes/Data` (the real data volume — **not** `/`,
  which reports the sealed read-only system snapshot and misleads).
- Largest files: walk the targets' own folders with `FileManager` (nested
  folders walked once), keep regular files ≥ 100 MB by allocated size, top 10.
  Each file is attributed to the one target whose `Measure` contains it
  (unique, because targets never double-count). Walked in-process rather than
  with `find` so odd filenames can't break parsing.
- All of this runs on a background `Task`; UI shows per-target progress and
  updates when done.

### 5.4 Classification (report-only output)
Each target carries a fixed category + cleanup command (validated list in
Appendix A). The popover groups rows under the three category headers, sorted by
size descending within each group. **Risky items show no command and no copy
button** — only an informational note on why to keep them (and, where one
exists, the safe tool-level alternative, e.g. `docker system prune`).

### 5.5 UI behavior
- **Menu-bar label shows free space, not percent used** — free GB is the number
  that matters when deciding whether to clean. Format: `7.7 GB` normally, with a
  `⚠︎` prefix when the data volume is ≥ 90% used (e.g. `⚠︎ 7.7 GB`). The
  label's tooltip and the popover header show the full line:
  "7.7 GB free of 228 GB · 97% used".
- Click → popover: free-space header bar (`ProgressView` filled to % used), then
  three collapsible category sections, then "Largest files", then a Rescan button.
- Each safe/rebuild row: size · name · one-line purpose · **[Copy cleanup]**
  (writes the command to the clipboard via `NSPasteboard`) · **[Reveal]**.
- No delete button anywhere. A footer line states: "This app never deletes
  files — commands are copied for you to review and run."

---

## 6. What's Left to the Builder

- Exact SwiftUI layout/styling of the popover (match the mockup's spirit; use
  system materials, `ProgressView` for the free-space bar).
- ~~Xcode project scaffolding~~ — done as a SwiftPM package instead (see
  "Build & run" below); no Xcode is installed, only the Command Line Tools.
- `Process` wrapper utility (run command, capture stdout, parse, error-handle).
- Progress reporting granularity (per-target tick vs. simple spinner).
- Formatting (bytes → human units; reuse `ByteCountFormatter`).
- Whether to persist the last scan between launches (nice-to-have, not v1).

---

## 7. Proposed Implementation Phases

1. ✅ **Scaffold** — SwiftUI `MenuBarExtra` app, non-sandboxed, runs and
   shows a static popover. (Done 2026-11-16.)
2. ✅ **Scanner core** — `Process` wrapper, `du`/`df` parsing, and all five
   `Measure` cases; background scan of the hardcoded `Target` list →
   `[ScanResult]`. Verified: matches `du -sk` to the kilobyte; full scan ≈4 s.
   (Done 2026-11-16.)
3. ✅ **Classifier + model** — categories, purposes, and cleanup commands
   (Appendix A) in `TargetCatalog`; §5.2 invariants enforced by
   `CatalogValidator` and checked in `CoreChecks`. (Pulled forward into phase 2.)
4. ✅ **Popover UI** — grouped ranked list with per-category totals,
   free-space header, copy/reveal buttons. Also pulled forward: the real
   menu-bar label (§5.5), a working Rescan with progress, "Nothing found" for
   empty categories, and a ⚠︎ marker on rows whose size may be low because
   part of the tree was unreadable. One scan runs at launch; after that only
   Rescan triggers one. (Done 2026-11-16.)
5. ✅ **Largest-files section** — top 10 files ≥ 100 MB, searched only inside
   the targets' folders (no whole-disk crawl), each labelled with the row
   that counts it; runs alongside the folder scan (≈4 s total). Error
   states: unreadable items are counted and shown. (Done 2026-11-16.)
6. **Polish** — formatting, footer safety note review, app icon/glyph.

Tests (in `Sources/CoreChecks`, run with `swift run CoreChecks`): unit-test the `du`/`df` output parsing, each `Measure` case against a
temp-directory fixture (including glob, pattern, and exclusion), and the
§5.2 invariants over the full target list. UI is verified by running the app.

### Build & run
- Layout: `StorageAnalysisCore` (pure logic library), `StorageAnalysis`
  (menu-bar app), `CoreChecks` (check runner).
- `./scripts/bundle.sh` → `build/StorageAnalysis.app` (ad-hoc signed, no
  entitlements = not sandboxed, `LSUIElement` = no Dock icon). Then
  `open build/StorageAnalysis.app`.
- `swift run storage-scan` prints a real scan (add `--kb` for exact
  kilobytes, to compare with `du -sk`).
- `swift run CoreChecks` runs the unit checks and exits non-zero on failure.
  Not `swift test`: with only the Command Line Tools, XCTest is missing and
  `swift test` silently runs zero swift-testing tests. If Xcode is installed
  later, these can move to a normal swift-testing target.

---

## Appendix A — Validated target list & categorization

Free space on `/System/Volumes/Data`:
- 2026-11-06: **14 GB free / 228 GB (94% full)**
- 2026-11-16: **7.7 GB free / 228 GB (97% full)**

"—" = path not present at that scan (already cleaned). Rows stay in the list
because these caches come back; the app hides them while empty.

### 🟢 Safe to delete (regenerates automatically)
| Target | Measure | 11-06 | 11-16 | Purpose | Cleanup command |
|---|---|---|---|---|---|
| HF partial downloads | `.files(~/.cache/huggingface, "*.incomplete")` | 4.25 GB | — | Interrupted model downloads (junk) | `find ~/.cache/huggingface -name "*.incomplete" -delete` |
| Aerial videos | `.directory(~/Library/Application Support/com.apple.wallpaper/aerials/videos)` | 6.6 GB | 3.8 GB | macOS aerial screensaver videos (re-download) | `rm -rf ~/Library/Application\ Support/com.apple.wallpaper/aerials/videos/*` |
| npm cache | `.directory(~/.npm/_cacache)` | 4.9 GB | 2.7 GB | npm package cache | `npm cache clean --force` |
| Yarn cache | `.directory(~/Library/Caches/Yarn)` | 3.7 GB | 4.5 GB | Yarn package cache | `yarn cache clean` |
| Chrome AI model | `.directory(.../Google/Chrome/OptGuideOnDeviceModel)` | 4.0 GB | 4.0 GB | Chrome on-device AI model (re-fetched) | `rm -rf ~/Library/Application\ Support/Google/Chrome/OptGuideOnDeviceModel` |
| npx cache | `.directory(~/.npm/_npx)` | 1.4 GB | 645 MB | One-off npx package cache | `rm -rf ~/.npm/_npx` |
| uv cache | `.directory(~/.cache/uv)` | 1.4 GB | — | Python uv cache | `uv cache clean` |
| Puppeteer browsers | `.directory(~/.cache/puppeteer)` | 1.4 GB | — | Puppeteer browser downloads | `rm -rf ~/.cache/puppeteer` |
| Headless browsers | `.sum([~/Library/Caches/ms-playwright, ~/Library/Caches/node-chromium])` | ~1.1 GB | — | Headless browser binaries | `rm -rf ~/Library/Caches/ms-playwright ~/Library/Caches/node-chromium` |
| App-update leftovers | `.glob(~/Library/Caches/*.ShipIt)` | ~3.5 GB | 8.8 MB | Completed app-update staging leftovers | `rm -rf ~/Library/Caches/*.ShipIt` |
| Misc build caches | `.sum([…/dotslash, …/puccinialin, …/pnpm, …/go-build])` under `~/Library/Caches` | ~2.0 GB | 774 MB | Misc build/tool caches | `rm -rf ~/Library/Caches/dotslash ~/Library/Caches/puccinialin ~/Library/Caches/pnpm ~/Library/Caches/go-build` |

Note: the misc-caches command spells out each path instead of using
`{a,b}` brace expansion, so the validator can check it word by word.

Note: the aerials target now measures `aerials/videos` (what the command
deletes), not the whole `aerials` folder, so the row and the command match.

### 🟡 Safe but rebuilds (slower next use)
| Target | Measure | 11-06 | 11-16 | Purpose | Cleanup command |
|---|---|---|---|---|---|
| Claude agent VM | `.directory(~/Library/Application Support/Claude/vm_bundles)` | 12 GB | 11 GB | Claude Desktop local-agent VM; re-provisions on next agent run | `rm -rf ~/Library/Application\ Support/Claude/vm_bundles` |
| Colima image cache | `.directory(~/Library/Caches/colima)` | ~0.3 GB | 317 MB | Downloaded base VM images; re-downloaded only when a new Colima VM is created. Does **not** touch the live VM in `~/.colima` | `rm -rf ~/Library/Caches/colima` |
| node-gyp | `.directory(~/Library/Caches/node-gyp)` | 228 MB | 228 MB | Native module build cache | `rm -rf ~/Library/Caches/node-gyp` |
| Electron downloads | `.sum([~/Library/Caches/electron, ~/Library/Caches/electron-builder])` | ~376 MB | 376 MB | Electron build downloads | `rm -rf ~/Library/Caches/electron ~/Library/Caches/electron-builder` |
| Prisma engines | `.directory(~/.cache/prisma)` | 192 MB | 192 MB | Prisma engine cache | `rm -rf ~/.cache/prisma` |

Colima's cache moved out of "Misc build caches": it was listed there but its
command never deleted it. It now has its own row, in "rebuilds" because removing
it means a multi-hundred-MB re-download on the next `colima start` with a fresh VM.

### 🔴 Risky / avoid (real data — never suggest deletion)
| Target | Measure | 11-06 | 11-16 | Why keep |
|---|---|---|---|---|
| Chrome profile | `.excluding(.directory(…/Google/Chrome), minus: [.directory(…/Chrome/OptGuideOnDeviceModel)])` | ~4 GB | ~4.2 GB | Browser profile: history, logins, extensions, bookmarks |
| Colima VM | `.directory(~/.colima)` | 5.5 GB | 14 GB | Live Docker/Colima container & VM data. Alternative: `docker system prune` |
| Claude sessions | `.directory(~/Library/Application Support/Claude/local-agent-mode-sessions)` | 1.1 GB | 1.1 GB | Actual Claude agent session data |
| Anki | `.directory(~/Library/Application Support/Anki2)` | 353 MB | 353 MB | Anki flashcard database — user data |
| HF models | `.excluding(.directory(~/.cache/huggingface), minus: [.files(~/.cache/huggingface, "*.incomplete")])` | varies | 300 MB | Models in active use; re-download is GBs |

`~/.colima` grew from 5.5 GB to 14 GB in ten days — now the single biggest item
on the list. It stays risky (live data), but the popover's note should point at
`docker system prune` as the safe way to shrink it.

---

## Appendix B — Open questions for later versions
- Scheduled background scans + menu-bar badge when reclaimable space crosses a
  threshold?
- Opt-in "confirm-each delete" mode (currently an anti-goal / out of scope)?
- User-editable target list vs. the curated built-in list?
