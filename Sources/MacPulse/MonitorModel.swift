import AppKit
import Combine
import ServiceManagement
import MacPulseCore

struct HistoryPoint: Identifiable {
    let id = UUID()
    let date: Date
    let cpu: Double?
    let memory: Double?
}

final class MonitorModel: ObservableObject {
    @Published private(set) var snapshot: MetricSnapshot?
    @Published private(set) var history: [HistoryPoint] = []
    @Published var settingsVisible = false
    @Published var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published var loginMessage: String?
    @Published var interval: Double = UserDefaults.standard.object(forKey: "sampleInterval") as? Double ?? 1 {
        didSet {
            UserDefaults.standard.set(interval, forKey: "sampleInterval")
            start()
        }
    }
    var onUpdate: (() -> Void)?
    private let queue = DispatchQueue(label: "com.seokmogu.macpulse.metrics", qos: .utility)
    private let collector = MetricCollector()
    private var timer: DispatchSourceTimer?

    func start(reset: Bool = false) {
        timer?.cancel()
        if reset {
            history.removeAll()
            queue.async { self.collector.reset() }
        }
        let next = DispatchSource.makeTimerSource(queue: queue)
        next.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(100))
        next.setEventHandler { [weak self] in
            guard let self else { return }
            let sample = self.collector.sample()
            DispatchQueue.main.async {
                self.snapshot = sample
                let percent = sample.memoryUsedBytes.map { Double($0) / Double(max(1, sample.memoryTotalBytes)) * 100 }
                self.history.append(HistoryPoint(date: sample.sampleTime, cpu: sample.cpuPercent, memory: percent))
                self.history.removeAll { $0.date < sample.sampleTime.addingTimeInterval(-60) }
                self.onUpdate?()
            }
        }
        timer = next
        next.resume()
    }

    func stop() { timer?.cancel(); timer = nil }

    var memoryPercent: Double? {
        guard let s = snapshot, let used = s.memoryUsedBytes, s.memoryTotalBytes > 0 else { return nil }
        return Double(used) / Double(s.memoryTotalBytes) * 100
    }

    static func percent(_ value: Double?) -> String {
        value.map { String(format: "%.0f%%", $0) } ?? "—"
    }

    static func size(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        let gb = Double(bytes) / 1_000_000_000
        return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
    }

    static func rate(_ bytes: Double?) -> String {
        guard let bytes else { return "—" }
        if bytes >= 1_000_000 { return String(format: "%.1f MB/s", bytes / 1_000_000) }
        if bytes >= 1_000 { return String(format: "%.0f KB/s", bytes / 1_000) }
        return String(format: "%.0f B/s", bytes)
    }
}
