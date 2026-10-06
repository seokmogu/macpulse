import Foundation

/// One point-in-time reading from the host's native resource counters.
public struct MetricSnapshot: Codable, Sendable {
    public let sampleTime: Date
    public let cpuPercent: Double?
    public let memoryUsedBytes: UInt64?
    public let memoryTotalBytes: UInt64
    public let networkDownloadBytesPerSecond: Double?
    public let networkUploadBytesPerSecond: Double?
    public let interfaceName: String?
    public let diskUsedBytes: UInt64?
    public let diskTotalBytes: UInt64?
    public let batteryPercent: Double?
    public let batteryState: String
    public let logicalCPUCount: Int
    public let errors: [String]

    public init(
        sampleTime: Date = Date(),
        cpuPercent: Double? = nil,
        memoryUsedBytes: UInt64? = nil,
        memoryTotalBytes: UInt64 = 0,
        networkDownloadBytesPerSecond: Double? = nil,
        networkUploadBytesPerSecond: Double? = nil,
        interfaceName: String? = nil,
        diskUsedBytes: UInt64? = nil,
        diskTotalBytes: UInt64? = nil,
        batteryPercent: Double? = nil,
        batteryState: String = "배터리 없음",
        logicalCPUCount: Int = 0,
        errors: [String] = []
    ) {
        self.sampleTime = sampleTime
        self.cpuPercent = cpuPercent
        self.memoryUsedBytes = memoryUsedBytes
        self.memoryTotalBytes = memoryTotalBytes
        self.networkDownloadBytesPerSecond = networkDownloadBytesPerSecond
        self.networkUploadBytesPerSecond = networkUploadBytesPerSecond
        self.interfaceName = interfaceName
        self.diskUsedBytes = diskUsedBytes
        self.diskTotalBytes = diskTotalBytes
        self.batteryPercent = batteryPercent
        self.batteryState = batteryState
        self.logicalCPUCount = logicalCPUCount
        self.errors = errors
    }
}
