import SwiftUI
import StorageAnalysisCore

/// Phase 1: static popover layout. Rows are placeholders until the scanner
/// (phase 2) and classifier (phase 3) exist.
struct PopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(SafetyCategory.allCases, id: \.self) { category in
                        CategorySection(category: category)
                    }
                }
            }
            .frame(maxHeight: 360)
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 380)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Storage Analysis").font(.headline)
            ProgressView(value: 0)
            Text("Not scanned yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Rescan") {}
                    .disabled(true) // enabled in phase 5
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

private struct CategorySection: View {
    let category: SafetyCategory
    @State private var expanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            Text("No results yet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
        } label: {
            Text("\(category.symbol) \(category.title)")
                .font(.subheadline.weight(.semibold))
        }
    }
}
