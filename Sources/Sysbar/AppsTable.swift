import SysbarCore
import SwiftUI

/// The apps using the most of the selected resource, highest first. Clicking a column header
/// chooses which column sorts. Which columns exist is up to the caller: the settings let the user
/// hide GPU and power, and remote machines only report CPU and memory.
struct AppsTable: View {
    let title: String
    let apps: [AppUsage]
    let columns: [AppSortKey]
    let rowLimit: Int
    let sort: AppSortKey
    let onSort: (AppSortKey) -> Void

    /// Three or more columns leave little room, so values switch to the compact form: "0.7G"
    /// instead of "700M" and "0.7W" instead of "743mW". With one or two columns the longer form
    /// is clearer and the columns can be wider.
    private var compact: Bool { columns.count >= 3 }

    private var columnWidth: CGFloat {
        switch columns.count {
        case 0...1: 64
        case 2: 56
        case 3: 48
        default: 44
        }
    }

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
                        Text(column.headerTitle)
                        if column == effectiveSort {
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                    }
                    .frame(width: columnWidth, alignment: .trailing)
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
                Text(Self.text(of: column, for: app, compact: compact))
                    .frame(width: columnWidth, alignment: .trailing)
                    .foregroundStyle(column == effectiveSort ? Color.primary : Color.secondary)
                    .help(Self.help(of: column, for: app))
            }
        }
        .font(.system(size: 11.5).monospacedDigit())
        // One element per app: "Safari", then "CPU 12%, Memory 340M".
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue(Self.spokenValue(of: app, columns: columns, compact: compact))
    }

    /// Zero GPU and power show as a dash so the columns stay readable. Network is a dash rather
    /// than "0K" when `nettop` could not be read at all.
    private static func text(of column: AppSortKey, for app: AppUsage, compact: Bool) -> String {
        switch column {
        case .cpu: Format.finePercent(app.cpu)
        case .memory: Format.memory(app.memoryBytes, compact: compact)
        case .gpu: app.gpu > 0.0005 ? Format.percent(app.gpu) : "–"
        case .power: compact ? Format.compactPower(app.powerWatts) : Format.detailedPower(app.powerWatts)
        case .network: app.networkTotal.map(Format.rate) ?? "–"
        }
    }

    /// The whole row for VoiceOver, with the two network directions spelled out.
    private static func spokenValue(of app: AppUsage, columns: [AppSortKey], compact: Bool) -> String {
        columns.map { column in
            let value = "\(column.columnTitle) \(text(of: column, for: app, compact: compact))"
            guard column == .network, let inbound = app.networkInbound, let outbound = app.networkOutbound else {
                return value
            }
            return value + ", " + L("download %1$@, upload %2$@", spokenRate(inbound), spokenRate(outbound))
        }
        .joined(separator: ", ")
    }

    /// The Network cell is one number to keep the table narrow; the two directions are in its
    /// tooltip, and VoiceOver hears them too.
    private static func help(of column: AppSortKey, for app: AppUsage) -> String {
        guard column == .network, let inbound = app.networkInbound, let outbound = app.networkOutbound else {
            return ""
        }
        return L("download %1$@, upload %2$@", spokenRate(inbound), spokenRate(outbound))
    }
}
