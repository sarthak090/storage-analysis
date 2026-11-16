/// The curated target list (PLAN.md Appendix A). Rules enforced by `CatalogValidator`.
public enum TargetCatalog {
    private static let appSupport = "~/Library/Application Support"
    private static let caches = "~/Library/Caches"
    private static let chrome = "\(appSupport)/Google/Chrome"
    private static let chromeModel = "\(chrome)/OptGuideOnDeviceModel"
    private static let huggingFace = "~/.cache/huggingface"

    public static let all: [Target] = safe + rebuild + risky

    // MARK: 🟢 Safe to delete

    static let safe: [Target] = [
        Target(
            id: "hf-incomplete",
            name: "HuggingFace partial downloads",
            measure: .files(root: huggingFace, pattern: "*.incomplete"),
            purpose: "Interrupted model downloads (junk)",
            category: .safe,
            cleanup: .shell(#"find ~/.cache/huggingface -name "*.incomplete" -delete"#)
        ),
        Target(
            id: "aerials",
            name: "Aerial screensaver videos",
            measure: .directory("\(appSupport)/com.apple.wallpaper/aerials/videos"),
            purpose: "macOS aerial screensaver videos (re-downloaded when used)",
            category: .safe,
            cleanup: .shell(#"rm -rf ~/Library/Application\ Support/com.apple.wallpaper/aerials/videos/*"#)
        ),
        Target(
            id: "npm-cache",
            name: "npm cache",
            measure: .directory("~/.npm/_cacache"),
            purpose: "npm package cache",
            category: .safe,
            cleanup: .tool("npm cache clean --force")
        ),
        Target(
            id: "yarn-cache",
            name: "Yarn cache",
            measure: .directory("\(caches)/Yarn"),
            purpose: "Yarn package cache",
            category: .safe,
            cleanup: .tool("yarn cache clean")
        ),
        Target(
            id: "chrome-model",
            name: "Chrome on-device AI model",
            measure: .directory(chromeModel),
            purpose: "Chrome's on-device AI model (re-fetched by Chrome)",
            category: .safe,
            cleanup: .shell(#"rm -rf ~/Library/Application\ Support/Google/Chrome/OptGuideOnDeviceModel"#)
        ),
        Target(
            id: "npx-cache",
            name: "npx cache",
            measure: .directory("~/.npm/_npx"),
            purpose: "One-off npx package cache",
            category: .safe,
            cleanup: .shell("rm -rf ~/.npm/_npx")
        ),
        Target(
            id: "uv-cache",
            name: "uv cache",
            measure: .directory("~/.cache/uv"),
            purpose: "Python uv package cache",
            category: .safe,
            cleanup: .tool("uv cache clean")
        ),
        Target(
            id: "puppeteer",
            name: "Puppeteer browsers",
            measure: .directory("~/.cache/puppeteer"),
            purpose: "Browsers downloaded by Puppeteer",
            category: .safe,
            cleanup: .shell("rm -rf ~/.cache/puppeteer")
        ),
        Target(
            id: "headless-browsers",
            name: "Headless browsers",
            measure: .sum([.directory("\(caches)/ms-playwright"), .directory("\(caches)/node-chromium")]),
            purpose: "Playwright and node-chromium browser binaries",
            category: .safe,
            cleanup: .shell("rm -rf ~/Library/Caches/ms-playwright ~/Library/Caches/node-chromium")
        ),
        Target(
            id: "shipit",
            name: "App-update leftovers",
            measure: .glob("\(caches)/*.ShipIt"),
            purpose: "Staging folders left behind by finished app updates",
            category: .safe,
            cleanup: .shell("rm -rf ~/Library/Caches/*.ShipIt")
        ),
        Target(
            id: "misc-build-caches",
            name: "Misc build caches",
            measure: .sum(["dotslash", "puccinialin", "pnpm", "go-build"].map { Measure.directory("\(caches)/\($0)") }),
            purpose: "dotslash, puccinialin, pnpm and Go build caches",
            category: .safe,
            cleanup: .shell("rm -rf ~/Library/Caches/dotslash ~/Library/Caches/puccinialin ~/Library/Caches/pnpm ~/Library/Caches/go-build")
        ),
    ]

    // MARK: 🟡 Safe but rebuilds

    static let rebuild: [Target] = [
        Target(
            id: "claude-vm",
            name: "Claude agent VM",
            measure: .directory("\(appSupport)/Claude/vm_bundles"),
            purpose: "Claude Desktop's local-agent VM; re-provisioned on the next agent run",
            category: .rebuild,
            cleanup: .shell(#"rm -rf ~/Library/Application\ Support/Claude/vm_bundles"#)
        ),
        Target(
            id: "colima-cache",
            name: "Colima image cache",
            measure: .directory("\(caches)/colima"),
            purpose: "Downloaded base VM images; re-downloaded only when a new Colima VM is created",
            category: .rebuild,
            cleanup: .shell("rm -rf ~/Library/Caches/colima"),
            note: "Does not touch the live VM in ~/.colima."
        ),
        Target(
            id: "node-gyp",
            name: "node-gyp",
            measure: .directory("\(caches)/node-gyp"),
            purpose: "Native module build cache",
            category: .rebuild,
            cleanup: .shell("rm -rf ~/Library/Caches/node-gyp")
        ),
        Target(
            id: "electron",
            name: "Electron downloads",
            measure: .sum([.directory("\(caches)/electron"), .directory("\(caches)/electron-builder")]),
            purpose: "Electron and electron-builder downloads",
            category: .rebuild,
            cleanup: .shell("rm -rf ~/Library/Caches/electron ~/Library/Caches/electron-builder")
        ),
        Target(
            id: "prisma",
            name: "Prisma engines",
            measure: .directory("~/.cache/prisma"),
            purpose: "Prisma engine cache",
            category: .rebuild,
            cleanup: .shell("rm -rf ~/.cache/prisma")
        ),
    ]

    // MARK: 🔴 Risky / avoid

    static let risky: [Target] = [
        Target(
            id: "chrome-profile",
            name: "Chrome profile",
            measure: .excluding(.directory(chrome), minus: [.directory(chromeModel)]),
            purpose: "Browser profile: history, logins, extensions, bookmarks",
            category: .risky,
            cleanup: nil
        ),
        Target(
            id: "colima-vm",
            name: "Colima VM",
            measure: .directory("~/.colima"),
            purpose: "Live Docker/Colima container and VM data",
            category: .risky,
            cleanup: nil,
            note: "To shrink it safely, run “docker system prune” with Colima running."
        ),
        Target(
            id: "claude-sessions",
            name: "Claude agent sessions",
            measure: .directory("\(appSupport)/Claude/local-agent-mode-sessions"),
            purpose: "Claude agent session data",
            category: .risky,
            cleanup: nil
        ),
        Target(
            id: "anki",
            name: "Anki",
            measure: .directory("\(appSupport)/Anki2"),
            purpose: "Anki flashcard collection — your data",
            category: .risky,
            cleanup: nil
        ),
        Target(
            id: "hf-models",
            name: "HuggingFace models",
            measure: .excluding(.directory(huggingFace), minus: [.files(root: huggingFace, pattern: "*.incomplete")]),
            purpose: "Downloaded models in use; re-downloading costs GBs",
            category: .risky,
            cleanup: nil
        ),
    ]
}
