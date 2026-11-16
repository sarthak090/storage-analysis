import AppKit
import SwiftUI
import StorageAnalysisCore

struct PopoverView: View {
    let model: ScanModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(SafetyCategory.allCases, id: \.self) { category in
                        CategorySection(category: category, model: model)
                    }
                }
                .padding(.trailing, 4)
            }
            // Fixed height: a MenuBarExtra window sizes to the ScrollView's
            // minimum, which is 0, so maxHeight alone collapses the list.
            .frame(height: 440)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 400)
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Storage Analysis").font(.headline)
            if let space = model.diskSpace {
                ProgressView(value: space.fractionUsed)
                    .tint(space.fractionUsed >= 0.9 ? .red : .accentColor)
                Text(Format.spaceSummary(space))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let error = model.diskSpaceError {
                Text("Couldn't read free space: \(error)")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                ProgressView(value: 0)
                Text("Reading free space…").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning)

                if model.isScanning {
                    ProgressView(value: Double(model.progress.done), total: Double(max(model.progress.total, 1)))
                        .frame(width: 80)
                    Text("\(model.progress.done) of \(model.progress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if let date = model.lastScanned {
                    Text("Scanned \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            Text("This app never deletes files — commands are copied for you to review and run.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Category section

private struct CategorySection: View {
    let category: SafetyCategory
    let model: ScanModel
    @State private var expanded = true

    var body: some View {
        let rows = model.rows(in: category)
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                if rows.isEmpty {
                    Text(model.lastScanned == nil ? "Scanning…" : "Nothing found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(rows) { result in
                        ResultRow(result: result)
                    }
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text("\(category.symbol) \(category.title)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !rows.isEmpty {
                    Text(Format.compact(model.total(in: category)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }
}

// MARK: - Row

private struct ResultRow: View {
    let result: ScanResult
    @State private var copied = false

    private var target: Target { result.target }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Format.compact(result.bytes))
                .font(.callout.weight(.medium))
                .monospacedDigit()
                .frame(width: 62, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(target.name).font(.callout)
                    if !result.errors.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                            .imageScale(.small)
                            .help("Size may be low — couldn't read everything:\n" + result.errors.joined(separator: "\n"))
                    }
                }
                Text(target.purpose)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = target.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)

            HStack(spacing: 2) {
                if let cleanup = target.cleanup {
                    Button {
                        copy(cleanup.command)
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .frame(width: 16)
                    }
                    .help(copied ? "Copied" : "Copy cleanup command:\n\(cleanup.command)")
                }
                if let path = Scanner.revealPath(for: target.measure) {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                    } label: {
                        Image(systemName: "magnifyingglass").frame(width: 16)
                    }
                    .help("Reveal in Finder")
                }
            }
            .buttonStyle(.borderless)
        }
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
