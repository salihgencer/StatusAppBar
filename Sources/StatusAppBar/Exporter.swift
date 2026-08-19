import Foundation
import AppKit

/// Anlık metrikleri ve spike log'u CSV veya JSON olarak dışa aktarır.
/// Kullanıcının gizliliği: dışa aktarılan veri yalnızca sayısal metrikler
/// ve proses adlarıdır; IP adresi dahil edilmez.
enum Exporter {

    enum Format { case csv, json }

    static func export(metrics: MetricsManager, format: Format) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .csv
            ? [.commaSeparatedText]
            : [.json]
        panel.nameFieldStringValue = format == .csv
            ? "statusappbar-report.csv"
            : "statusappbar-report.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let data: String
        switch format {
        case .csv: data = buildCSV(metrics: metrics)
        case .json: data = buildJSON(metrics: metrics)
        }

        try? data.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - CSV

    private static func buildCSV(metrics: MetricsManager) -> String {
        var lines: [String] = []

        lines.append("Section,Metric,Value")
        lines.append("CPU,Total,\(String(format: "%.1f%%", metrics.cpu.total * 100))")
        lines.append("CPU,Load 1m,\(String(format: "%.2f", metrics.cpu.load[0]))")
        lines.append("CPU,P-Cores,\(metrics.cpu.pCores)")
        lines.append("CPU,E-Cores,\(metrics.cpu.eCores)")

        lines.append("Memory,Used,\(Fmt.bytes(metrics.memory.used))")
        lines.append("Memory,Free,\(Fmt.bytes(metrics.memory.free))")
        lines.append("Memory,Swap Used,\(Fmt.bytes(metrics.memory.swapUsed))")
        lines.append("Memory,Compressed,\(Fmt.bytes(metrics.memory.compressed))")

        lines.append("GPU,Utilization,\(String(format: "%.1f%%", metrics.gpu.utilization * 100))")
        lines.append("GPU,Name,\(metrics.gpu.name)")

        for vol in metrics.disk.volumes {
            lines.append("Disk,\(vol.name) Used,\(Fmt.bytes(vol.used))")
            lines.append("Disk,\(vol.name) Free,\(Fmt.bytes(vol.free))")
        }
        lines.append("Disk,Read/s,\(Fmt.rate(metrics.disk.readPerSec))")
        lines.append("Disk,Write/s,\(Fmt.rate(metrics.disk.writePerSec))")

        lines.append("Network,Down/s,\(Fmt.rate(metrics.network.downPerSec))")
        lines.append("Network,Up/s,\(Fmt.rate(metrics.network.upPerSec))")

        if metrics.power.hasBattery {
            lines.append("Power,Level,\(String(format: "%.0f%%", metrics.power.level * 100))")
            lines.append("Power,Health,\(String(format: "%.0f%%", metrics.power.healthPercent))")
            lines.append("Power,Cycles,\(metrics.power.cycleCount)")
            lines.append("Power,Watts,\(String(format: "%.1f", metrics.power.watts))")
        }

        lines.append("Thermal,State,\(metrics.thermal.label)")
        lines.append("Health,Score,\(metrics.health)")
        lines.append("System,Uptime,\(Fmt.uptime(metrics.uptime))")

        if !metrics.spikeLog.isEmpty {
            lines.append("")
            lines.append("Spike Log")
            lines.append("Time,Type,Peak,Culprit,Culprit Value")
            let df = ISO8601DateFormatter()
            for spike in metrics.spikeLog {
                let peak = String(format: "%.1f%%", spike.peakValue * 100)
                lines.append("\(df.string(from: spike.timestamp)),\(spike.kind.rawValue),\(peak),\(spike.culpritName),\(spike.culpritValue)")
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - JSON

    private static func buildJSON(metrics: MetricsManager) -> String {
        let df = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "timestamp": df.string(from: Date()),
            "health": metrics.health,
            "uptime_seconds": Int(metrics.uptime),
            "cpu": [
                "total": metrics.cpu.total,
                "load": metrics.cpu.load,
                "p_cores": metrics.cpu.pCores,
                "e_cores": metrics.cpu.eCores
            ],
            "memory": [
                "used_bytes": metrics.memory.used,
                "free_bytes": metrics.memory.free,
                "total_bytes": metrics.memory.total,
                "swap_used_bytes": metrics.memory.swapUsed,
                "compressed_bytes": metrics.memory.compressed
            ],
            "gpu": [
                "utilization": metrics.gpu.utilization,
                "name": metrics.gpu.name
            ],
            "network": [
                "down_bytes_per_sec": metrics.network.downPerSec,
                "up_bytes_per_sec": metrics.network.upPerSec
            ],
            "thermal": [
                "state": metrics.thermal.label,
                "severity": metrics.thermal.severity
            ]
        ]

        var disks: [[String: Any]] = []
        for vol in metrics.disk.volumes {
            disks.append(["name": vol.name, "total": vol.total, "free": vol.free])
        }
        dict["disks"] = disks

        if metrics.power.hasBattery {
            dict["power"] = [
                "level": metrics.power.level,
                "health_percent": metrics.power.healthPercent,
                "cycles": metrics.power.cycleCount,
                "watts": metrics.power.watts,
                "charging": metrics.power.isCharging,
                "temperature": metrics.power.temperature
            ]
        }

        var spikes: [[String: Any]] = []
        for spike in metrics.spikeLog {
            spikes.append([
                "timestamp": df.string(from: spike.timestamp),
                "kind": spike.kind.rawValue,
                "peak": spike.peakValue,
                "culprit": spike.culpritName,
                "culprit_pid": spike.culpritPID
            ])
        }
        if !spikes.isEmpty { dict["spike_log"] = spikes }

        guard let data = try? JSONSerialization.data(withJSONObject: dict,
                                                      options: [.prettyPrinted, .sortedKeys]) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
