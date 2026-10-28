import SysbarCore
import SwiftUI

/// The apps using the most of the selected resource, highest first. Clicking a column header
/// chooses which column sorts. Which columns exist is up to the caller: the settings let the user
/// hide GPU and power, and remote machines only report CPU and memory.
struct AppsTable: View {
    private static let columnWidth: CGFloat = 46

    let title: String
    let apps: [AppUsage]
    let columns: [AppSortKey]
    let rowLimit: Int
    let sort: AppSortKey
    let onSort: (AppSortKey) -> Void

    /// The chosen sort column may have been hidden; fall back to the first one that is shown.
    private var effectiveSort: AppSortKey {
        columns.contains(sort) ? sort : (columns.first ?? .cpu)
    }

    var body: some View {
        let rows = AppUsageCalculator.top(apps, by: effectiveSort, limit: rowLimit)

        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            header
            if rows.isEmpty {
                Text(L("Measuring…")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(rows, id: \.name) { row($0) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text(L("App")).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { column in
                Button { onSort(column) } label: {
                    HStack(spacing: 2) {
                        Text(column.columnTitle)
                        if column == effectiveSort {
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                    }
                    .frame(width: Self.columnWidth, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .foregroundStyle(column == effectiveSort ? Color.primary : Color.secondary)
                .accessibilityLabel(L("Sort by %@ column", column.columnTitle))
                .accessibilityAddTraits(column == effectiveSort ? .isSelected : [])
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func row(_ app: AppUsage) -> some View {
        HStack(spacing: 0) {
            Text(app.name).lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { column in
                Text(Self.text(of: column, for: app))
                    .frame(width: Self.columnWidth, alignment: .trailing)
                    .foregroundStyle(column == effectiveSort ? Color.primary : Color.secondary)
            }
        }
        .font(.system(size: 11.5).monospacedDigit())
        // One element per app: "Safari", then "CPU 12%, Memory 340M".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue(
            columns.map { "\($0.columnTitle) \(Self.text(of: $0, for: app))" }.joined(separator: ", ")
        )
    }

    /// Zero GPU and power show as a dash so the columns stay readable.
    private static func text(of column: AppSortKey, for app: AppUsage) -> String {
        switch column {
        case .cpu: Format.finePercent(app.cpu)
        case .memory: Format.memory(app.memoryBytes)
        case .gpu: app.gpu > 0.0005 ? Format.percent(app.gpu) : "–"
        case .power: powerText(app.powerWatts)
        }
    }

    /// App energy is tiny next to system power, so values under one watt are shown in milliwatts.
    private static func powerText(_ watts: Double) -> String {
        if watts >= 1 { return Format.compactWatts(watts) }
        return watts >= 0.005 ? String(format: "%.0fmW", watts * 1_000) : "–"
    }
}
