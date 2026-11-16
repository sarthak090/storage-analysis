import AppKit
import SwiftUI
import StorageAnalysisCore

struct PopoverView: View {
    let model: ScanModel
    @State private var loginItem = LoginItem()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SummaryHeader(model: model)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(SafetyCategory.allCases, id: \.self) { category in
                        CategoryCard(category: category, model: model)
                    }
                    LargestFilesCard(model: model)
                }
                .padding(16)
            }
            // Fixed height: a MenuBarExtra window sizes to the ScrollView's
            // minimum, which is 0, so maxHeight alone collapses the list.
            .frame(height: 430)
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 400)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("Open at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.set($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .font(.caption)
            if let error = loginItem.error {
                Text("Couldn't change login item: \(error)")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label("Never deletes anything — commands are copied for you to review and run.", systemImage: "lock.shield")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Summary header (hero number + segmented bar + legend)

private struct SummaryHeader: View {
    let model: ScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Storage")
                    .font(.headline)
                Spacer()
                scanStatus
                Button {
                    Task { await model.scan() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isScanning)
                .help("Rescan")
            }

            if let space = model.diskSpace {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(Format.compact(space.availableBytes))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("free of \(Format.compact(space.totalBytes))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Format.percent(space.fractionUsed)) used")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(space.fractionUsed >= Format.warningFraction ? .red : .secondary)
                }

                let breakdown = model.breakdown ?? StorageBreakdown(space: space, results: [])
                SegmentedBar(breakdown: breakdown)
                Legend(breakdown: breakdown, scanned: model.lastScanned != nil)
            } else if let error = model.diskSpaceError {
                Text("Couldn't read free space: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("Reading disk…")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var scanStatus: some View {
        if model.isScanning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Scanning \(model.progress.done) of \(model.progress.total)")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let date = model.lastScanned {
            Text("Scanned \(date.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SegmentedBar: View {
    let breakdown: StorageBreakdown

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 1.5) {
                ForEach(breakdown.segments.filter { $0.bytes > 0 }, id: \.kind) { segment in
                    Rectangle()
                        .fill(Theme.color(segment.kind))
                        .frame(width: max(2, geo.size.width * breakdown.fraction(segment.kind)))
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
        }
        .frame(height: 10)
        .clipShape(Capsule())
        .accessibilityElement()
        .accessibilityLabel(breakdown.segments.map { "\($0.kind.title) \(Format.compact($0.bytes))" }.joined(separator: ", "))
    }
}

private struct Legend: View {
    let breakdown: StorageBreakdown
    let scanned: Bool

    var body: some View {
        // Free is already the headline number, so the legend skips it.
        let kinds: [StorageBreakdown.Kind] = scanned
            ? [.safe, .rebuild, .risky, .other]
            : [.other]
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 6) {
            ForEach(kinds, id: \.self) { kind in
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.color(kind))
                        .frame(width: 8, height: 8)
                    Text(kind.title)
                        .foregroundStyle(.secondary)
                    Text(Format.compact(breakdown.bytes(kind)))
                        .monospacedDigit()
                }
                .font(.caption)
            }
        }
    }
}

// MARK: - Category card

private struct CategoryCard: View {
    let category: SafetyCategory
    let model: ScanModel
    @State private var expanded = true
    @State private var copiedAll = false

    var body: some View {
        let rows = model.rows(in: category)
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(
                title: category.title,
                total: rows.isEmpty ? nil : model.total(in: category),
                tint: Theme.color(category),
                expanded: $expanded
            )

            if expanded {
                Card {
                    if rows.isEmpty {
                        Text(model.lastScanned == nil ? "Scanning…" : "Nothing found")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, result in
                            if index > 0 { Divider().padding(.leading, 48) }
                            ResultRow(result: result)
                        }
                        if category == .safe, rows.count > 1 {
                            Divider()
                            copyAllButton(rows)
                        }
                    }
                }
                Text(Theme.footnote(category))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func copyAllButton(_ rows: [ScanResult]) -> some View {
        let commands = rows.compactMap(\.target.cleanup?.command)
        return Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commands.joined(separator: "\n"), forType: .string)
            copiedAll = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copiedAll = false
            }
        } label: {
            HStack {
                Image(systemName: copiedAll ? "checkmark" : "doc.on.doc")
                Text(copiedAll ? "Copied \(commands.count) commands" : "Copy all \(commands.count) commands")
                Spacer()
                Text(Format.compact(model.total(in: category)))
                    .monospacedDigit()
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(Theme.color(category))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copies every command above, one per line, for you to review before running.\n\n" + commands.joined(separator: "\n"))
    }
}

private struct SectionHeader: View {
    let title: String
    let total: Int64?
    let tint: Color
    @Binding var expanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(tint).frame(width: 8, height: 8)
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.4)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                Spacer()
                if let total {
                    Text(Format.compact(total))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(expanded ? "expanded" : "collapsed")")
    }
}

// MARK: - Rows

private struct ResultRow: View {
    let result: ScanResult
    @State private var copied = false
    @State private var hovering = false

    private var target: Target { result.target }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            IconTile(symbol: Theme.symbol(for: target.id), tint: Theme.color(target.category))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(target.name).font(.callout.weight(.medium))
                    if !result.errors.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .imageScale(.small)
                            .help("Size may be low — couldn't read everything:\n" + result.errors.joined(separator: "\n"))
                    }
                }
                Text(target.note.map { "\(target.purpose). \($0)" } ?? target.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.compact(result.bytes))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                HStack(spacing: 8) {
                    if let cleanup = target.cleanup {
                        Button { copy(cleanup.command) } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        }
                        .help(copied ? "Copied" : "Copy cleanup command:\n\(cleanup.command)")
                    }
                    if let path = Scanner.revealPath(for: target.measure) {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .help("Reveal in Finder")
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(hovering || copied ? .primary : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

// MARK: - Largest files

private struct LargestFilesCard: View {
    let model: ScanModel
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Largest files", total: nil, tint: .accentColor, expanded: $expanded)
            if expanded {
                Card {
                    if let report = model.largeFiles {
                        if report.files.isEmpty {
                            Text("No files over 100 MB in the scanned folders")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .padding(12)
                        } else {
                            ForEach(Array(report.files.enumerated()), id: \.element.id) { index, file in
                                if index > 0 { Divider().padding(.leading, 48) }
                                LargeFileRow(file: file)
                            }
                        }
                    } else {
                        Text("Searching…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                }
                let skipped = model.largeFiles?.unreadableCount ?? 0
                Text(skipped > 0
                     ? "Files of 100 MB or more inside the folders above. \(skipped) item(s) couldn't be read."
                     : "Files of 100 MB or more inside the folders above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct LargeFileRow: View {
    let file: LargeFile
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            IconTile(symbol: "doc", tint: file.owner.map { Theme.color($0.category) } ?? .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.owner.map { "In \($0.name)" } ?? file.displayFolder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.compact(file.bytes))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(hovering ? .primary : .secondary)
                .help("Reveal in Finder\n\(file.path)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .onHover { hovering = $0 }
    }
}
