import Darwin
import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

/// Command-line checks for hosts where XCTest is unavailable in the installed
/// CommandLineTools image. Compile this file with the core sources directly;
/// it intentionally writes no samples to disk.
@main
struct StandaloneChecks {
    static func main() {
        let previous = MetricCalculations.CPUCounterSnapshot(
            user: 10,
            system: 20,
            nice: 30,
            idle: UInt32.max - 1
        )
        let current = MetricCalculations.CPUCounterSnapshot(
            user: 11,
            system: 20,
            nice: 30,
            idle: 1
        )
        require(
            MetricCalculations.cpuPercent(previous: nil, current: previous) == nil,
            "CPU baseline should be nil"
        )
        require(
            abs((MetricCalculations.cpuPercent(previous: previous, current: current) ?? -1) - 25) < 0.0001,
            "CPU UInt32 wrap calculation failed"
        )
        require(
            MetricCalculations.counterRate(
                previous: 100,
                current: 90,
                previousTime: 1,
                currentTime: 2
            ) == nil,
            "Counter reset should invalidate the rate"
        )

        let changedInterface = MetricCalculations.networkRates(
            previousInterface: "en0",
            currentInterface: "en1",
            previousDownload: 1,
            currentDownload: 2,
            previousUpload: 1,
            currentUpload: 2,
            previousTime: 1,
            currentTime: 2
        )
        require(
            changedInterface.download == nil && changedInterface.upload == nil,
            "Interface changes should invalidate rates"
        )
        require(
            MetricCalculations.memoryUsedBytes(
                activePages: 1,
                inactivePages: 2,
                wiredPages: 3,
                compressorPages: 4,
                purgeablePages: 100,
                externalPages: 100,
                pageSize: 4_096,
                physicalMemoryBytes: 1_024
            ) == 0,
            "Memory subtraction should clamp underflow"
        )
        require(
            MetricCalculations.memoryUsedBytes(
                activePages: 100,
                inactivePages: 100,
                wiredPages: 100,
                compressorPages: 100,
                purgeablePages: 0,
                externalPages: 0,
                pageSize: 4_096,
                physicalMemoryBytes: 4_096
            ) == 4_096,
            "Memory result should clamp to physical memory"
        )

        let collector = MetricCollector()
        let first = collector.sample()
        usleep(1_000_000)
        let second = collector.sample()
        require(first.cpuPercent == nil, "First CPU sample must have no baseline")
        require(second.cpuPercent.map { (0...100).contains($0) } == true, "Live CPU out of range")
        require(second.memoryTotalBytes > 0, "Physical memory missing")
        require(second.memoryUsedBytes.map { $0 <= second.memoryTotalBytes } == true, "Live memory out of range")
        require(second.diskUsedBytes != nil && second.diskTotalBytes != nil, "Disk capacity missing")
        if let total = second.diskTotalBytes, let used = second.diskUsedBytes { require(used <= total, "Disk used exceeds total") }
        collector.reset()
        require(collector.sample().cpuPercent == nil, "Reset must clear CPU baseline")
        print("PASS: arithmetic edge cases, live system counters, and baseline reset")
    }
}
