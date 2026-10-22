import SysbarCore
import SwiftUI

/// The popover content for a remote machine: connection status, cards, and its busiest processes.
struct RemoteView: View {
    @ObservedObject var monitor: RemoteMonitor
    /// The cards this device is set to show; the ones its machine cannot report are skipped.
    let cards: [RemoteCard]
    let temperatureUnit: TemperatureUnit
    let rowLimit: Int
    let onRetry: () -> Void

    @State private var sort: AppSortKey = .cpu

    var body: some View {
        let samples = monitor.history.items

        VStack(alignment: .leading, spacing: 12) {
            statusRow(latest: samples.last)
            if let latest = samples.last {
                let visible = RemoteCard.visible(chosen: cards, available: RemoteCard.available(in: samples))

                if !visible.isEmpty {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 8),
                            count: CardLayout.columns(forCount: visible.count)
                        ),
                        spacing: 8
                    ) {
                        ForEach(visible, id: \.self) { card(for: $0, samples, latest) }
                    }
                }
                AppsTable(
                    title: L("Top processes"),
                    apps: Self.apps(from: latest.processes),
                    columns: [.cpu, .memory], rowLimit: rowLimit, sort: sort, onSort: { sort = $0 }
                )
            }
        }
    }

    // MARK: Status

    @ViewBuilder
    private func statusRow(latest: RemoteSnapshot?) -> some View {
        switch monitor.state {
        case .idle:
            EmptyView()
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(L("Connecting…")).foregroundStyle(.secondary)
            }
            .font(.callout)
        case .live:
            EmptyView()
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(LoadLevel.high.color)
                    .fixedSize(horizontal: false, vertical: true)
                Button(L("Try again"), action: onRetry)
            }
        }
    }

    // MARK: Cards

    @ViewBuilder
    private func card(for card: RemoteCard, _ samples: [RemoteSnapshot], _ latest: RemoteSnapshot) -> some View {
        switch card {
        case .cpu: cpuCard(samples, latest)
        case .memory: memoryCard(samples, latest)
        case .load: loadCard(samples, latest)
        case .network: networkCard(samples, latest)
        case .disk: diskCard(samples, latest)
        case .gpu: gpuCard(samples, latest)
        }
    }

    private func cpuCard(_ samples: [RemoteSnapshot], _ latest: RemoteSnapshot) -> some View {
        let series = samples.compactMap(\.cpuUsage)
        return card(
            title: L("CPU"), symbol: "cpu",
            value: latest.cpuUsage.map(Format.percent) ?? "–",
            note: latest.cpuTemperature.map { temperatureUnit.format(celsius: $0) } ?? "",
            help: statsHelp(series, Format.percent),
            series: series, range: 0...1,
            load: latest.cpuUsage.map { LoadLevel(fraction: $0) }
        )
    }

    private func memoryCard(_ samples: [RemoteSnapshot], _ latest: RemoteSnapshot) -> some View {
        card(
            title: L("Memory"), symbol: "memorychip",
            value: latest.memory.map { Format.gigabytes($0.usedBytes) } ?? "–",
            note: latest.memory.map { Format.totalMemory($0.totalBytes) } ?? "", help: "",
            series: samples.compactMap { $0.memory?.fraction }, range: 0...1,
            load: latest.memory.map { LoadLevel(fraction: $0.fraction) }
        )
    }

    private func loadCard(_ samples: [RemoteSnapshot], _ latest: RemoteSnapshot) -> some View {
        let average = latest.load
        return card(
            title: L("Load"), symbol: "gauge.with.dots.needle.33percent",
            value: average.map { String(format: "%.2f", $0.one) } ?? "–",
            note: average.map { String(format: "%.2f · %.2f", $0.five, $0.fifteen) } ?? "",
            help: L("Load average: 1 min (large number), 5 min and 15 min"),
            series: samples.compactMap { $0.load?.one }, range: nil,
            load: latest.loadFraction.map { LoadLevel(fraction: $0) }
        )
    }

    private func networkCard(_ samples: [RemoteSnapshot], _ latest: RemoteSnapshot) -> some View {
        card(
            title: L("Network"), symbol: "arrow.up.arrow.down",
            value: latest.network.map { Format.rate($0.total) } ?? "–", unit: "/s",
            note: latest.network.map { "↓\(Format.rate($0.inbound)) ↑\(Format.rate($0.outbound))" } ?? "",
            help: L("↓ Download · ↑ Upload"),
            series: samples.compactMap { $0.network?.total }, range: nil, load: nil
        )
    }

    private func diskCard(_ samples: [RemoteSnapshot], _ latest: RemoteSnapshot) -> some View {
        card(
            title: L("Disk"), symbol: "internaldrive",
            value: latest.disk.map { Format.rate($0.total) } ?? "–", unit: "/s",
            note: latest.disk.map { "↓\(Format.rate($0.inbound)) ↑\(Format.rate($0.outbound))" } ?? "",
            help: L("↓ Read · ↑ Write"),
            series: samples.compactMap { $0.disk?.total }, range: nil, load: nil
        )
    }

    private func gpuCard(_ samples: [RemoteSnapshot], _ latest: RemoteSnapshot) -> some View {
        let series = samples.compactMap(\.gpuUsage)
        return card(
            title: L("GPU"), symbol: "display",
            value: latest.gpuUsage.map(Format.percent) ?? "–",
            note: "", help: statsHelp(series, Format.percent),
            series: series, range: 0...1,
            load: latest.gpuUsage.map { LoadLevel(fraction: $0) }
        )
    }

    private func card(
        title: String, symbol: String, value: String, unit: String = "", note: String, help: String,
        series: [Double], range: ClosedRange<Double>?, load: LoadLevel?
    ) -> some View {
        MetricCard(
            title: title, symbol: symbol, value: value, unit: unit, note: note,
            series: series, capacity: monitor.history.capacity, range: range,
            tint: load?.color ?? ActivityColors.color, help: help
        )
    }

    // MARK: Helpers

    private func statsHelp(_ series: [Double], _ format: (Double) -> String) -> String {
        guard let stats = SeriesStats.of(series) else { return "" }
        return L("Peak %@", format(stats.max))
    }

    /// Processes with the same name (a server's many workers) fold into one row.
    private static func apps(from processes: [RemoteProcess]) -> [AppUsage] {
        Dictionary(grouping: processes, by: \.name).map { name, items in
            AppUsage(
                name: name,
                cpu: items.map(\.cpu).reduce(0, +),
                memoryBytes: items.map(\.memoryBytes).reduce(0, +),
                gpu: 0, powerWatts: 0
            )
        }
    }
}
