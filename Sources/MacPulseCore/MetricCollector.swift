import Foundation
import Darwin
import IOKit
import IOKit.ps
import SystemConfiguration

/// Pure counter and memory calculations used by `MetricCollector` and its tests.
///
/// These helpers intentionally do not read the host. Keeping arithmetic separate
/// makes wraparound, reset, and clamping behavior explicit and testable.
internal enum MetricCalculations {
    internal struct CPUCounterSnapshot: Equatable {
        let user: UInt32
        let system: UInt32
        let nice: UInt32
        let idle: UInt32

        internal init(user: UInt32, system: UInt32, nice: UInt32, idle: UInt32) {
            self.user = user
            self.system = system
            self.nice = nice
            self.idle = idle
        }
    }

    /// Returns total host CPU utilization between two HOST_CPU_LOAD_INFO reads.
    /// Mach exposes each tick counter as UInt32, so subtraction intentionally
    /// uses wrapping arithmetic to handle a counter crossing UInt32.max.
    internal static func cpuPercent(
        previous: CPUCounterSnapshot?,
        current: CPUCounterSnapshot
    ) -> Double? {
        guard let previous else { return nil }

        let user = UInt64(current.user &- previous.user)
        let system = UInt64(current.system &- previous.system)
        let nice = UInt64(current.nice &- previous.nice)
        let idle = UInt64(current.idle &- previous.idle)
        let total = user &+ system &+ nice &+ idle
        guard total > 0 else { return nil }

        let active = user &+ system &+ nice
        return min(100, max(0, Double(active) / Double(total) * 100))
    }

    /// Returns a non-negative rate only when the counter and monotonic clock
    /// both moved forward. A decrease indicates a source counter reset.
    internal static func counterRate(
        previous: UInt64?,
        current: UInt64,
        previousTime: TimeInterval?,
        currentTime: TimeInterval
    ) -> Double? {
        guard let previous, let previousTime,
              current >= previous,
              currentTime > previousTime else {
            return nil
        }
        return Double(current - previous) / (currentTime - previousTime)
    }

    /// Calculates both network rates for one selected interface. Changing the
    /// selected interface invalidates the old baseline to avoid VPN/physical
    /// interface double counting and misleading spikes.
    internal static func networkRates(
        previousInterface: String?,
        currentInterface: String,
        previousDownload: UInt64?,
        currentDownload: UInt64,
        previousUpload: UInt64?,
        currentUpload: UInt64,
        previousTime: TimeInterval?,
        currentTime: TimeInterval
    ) -> (download: Double?, upload: Double?) {
        guard previousInterface == currentInterface else {
            return (nil, nil)
        }
        return (
            counterRate(
                previous: previousDownload,
                current: currentDownload,
                previousTime: previousTime,
                currentTime: currentTime
            ),
            counterRate(
                previous: previousUpload,
                current: currentUpload,
                previousTime: previousTime,
                currentTime: currentTime
            )
        )
    }

    /// Computes resident physical memory as
    /// `active + inactive + wired + compressor - purgeable - external` pages.
    /// Purgeable and external pages are treated as reclaimable; arithmetic is
    /// saturating and the final result is clamped to physical memory.
    internal static func memoryUsedBytes(
        activePages: UInt64,
        inactivePages: UInt64,
        wiredPages: UInt64,
        compressorPages: UInt64,
        purgeablePages: UInt64,
        externalPages: UInt64,
        pageSize: UInt64,
        physicalMemoryBytes: UInt64
    ) -> UInt64 {
        guard pageSize > 0, physicalMemoryBytes > 0 else { return 0 }

        func saturatingAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
            lhs > UInt64.max - rhs ? UInt64.max : lhs + rhs
        }

        func saturatingMultiply(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
            guard lhs == 0 || rhs <= UInt64.max / lhs else { return UInt64.max }
            return lhs * rhs
        }

        let pages = saturatingAdd(
            saturatingAdd(activePages, inactivePages),
            saturatingAdd(wiredPages, compressorPages)
        )
        let reclaimablePages = saturatingAdd(purgeablePages, externalPages)
        let residentPages = pages > reclaimablePages ? pages - reclaimablePages : 0
        let usedBytes = saturatingMultiply(residentPages, pageSize)
        return min(usedBytes, physicalMemoryBytes)
    }
}

/// Collects native macOS metrics. Instances are intended to be called from one
/// dedicated serial queue; this type deliberately does not add its own locking
/// or concurrency machinery.
public final class MetricCollector {
    private struct NetworkBaseline {
        let interfaceName: String
        let downloadBytes: UInt64
        let uploadBytes: UInt64
        let monotonicTime: TimeInterval
    }

    private struct InterfaceCounters {
        let name: String
        let downloadBytes: UInt64
        let uploadBytes: UInt64
    }

    private let hostPort: host_t
    private var previousCPU: MetricCalculations.CPUCounterSnapshot?
    private var previousNetwork: NetworkBaseline?

    public init() {
        hostPort = mach_host_self()
    }

    deinit {
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    /// Clears CPU and network baselines. The next sample reports nil rates until
    /// the following sample establishes a valid interval.
    public func reset() {
        previousCPU = nil
        previousNetwork = nil
    }

    public func sample() -> MetricSnapshot {
        let sampleTime = Date()
        let monotonicTime = ProcessInfo.processInfo.systemUptime
        var errors: [String] = []

        let cpuPercent = readCPU(errors: &errors)
        let memory = readMemory(errors: &errors)
        let network = readNetwork(monotonicTime: monotonicTime, errors: &errors)
        let disk = readDisk(errors: &errors)
        let battery = readBattery(errors: &errors)

        return MetricSnapshot(
            sampleTime: sampleTime,
            cpuPercent: cpuPercent,
            memoryUsedBytes: memory.used,
            memoryTotalBytes: memory.total,
            networkDownloadBytesPerSecond: network.downloadRate,
            networkUploadBytesPerSecond: network.uploadRate,
            interfaceName: network.interfaceName,
            diskUsedBytes: disk.used,
            diskTotalBytes: disk.total,
            batteryPercent: battery.percent,
            batteryState: battery.state,
            logicalCPUCount: ProcessInfo.processInfo.processorCount,
            errors: errors
        )
    }

    private func readCPU(errors: inout [String]) -> Double? {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            errors.append("CPU 정보를 읽지 못했습니다 (mach error \(result)).")
            return nil
        }

        let current = MetricCalculations.CPUCounterSnapshot(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            // Darwin's host_cpu_load_info ordering is user, system, idle, nice.
            nice: info.cpu_ticks.3,
            idle: info.cpu_ticks.2
        )
        let cpuPercent = MetricCalculations.cpuPercent(previous: previousCPU, current: current)
        previousCPU = current
        return cpuPercent
    }

    private func readMemory(errors: inout [String]) -> (used: UInt64?, total: UInt64) {
        let physicalMemory = UInt64(ProcessInfo.processInfo.physicalMemory)
        guard physicalMemory > 0 else {
            errors.append("물리 메모리 용량을 확인하지 못했습니다.")
            return (nil, 0)
        }

        var pageSize = vm_size_t(0)
        let pageResult = host_page_size(hostPort, &pageSize)
        guard pageResult == KERN_SUCCESS, pageSize > 0 else {
            errors.append("메모리 페이지 크기를 확인하지 못했습니다 (mach error \(pageResult)).")
            return (nil, physicalMemory)
        }

        var info = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            errors.append("메모리 통계를 읽지 못했습니다 (mach error \(result)).")
            return (nil, physicalMemory)
        }

        let used = MetricCalculations.memoryUsedBytes(
            activePages: UInt64(info.active_count),
            inactivePages: UInt64(info.inactive_count),
            wiredPages: UInt64(info.wire_count),
            compressorPages: UInt64(info.compressor_page_count),
            purgeablePages: UInt64(info.purgeable_count),
            externalPages: UInt64(info.external_page_count),
            pageSize: UInt64(pageSize),
            physicalMemoryBytes: physicalMemory
        )
        return (used, physicalMemory)
    }

    private func readNetwork(
        monotonicTime: TimeInterval,
        errors: inout [String]
    ) -> (interfaceName: String?, downloadRate: Double?, uploadRate: Double?) {
        let counters = interfaceCounters(errors: &errors)
        guard let selected = selectInterface(from: counters, errors: &errors) else {
            previousNetwork = nil
            return (nil, nil, nil)
        }

        let rates: (download: Double?, upload: Double?)
        if let previousNetwork {
            rates = MetricCalculations.networkRates(
                previousInterface: previousNetwork.interfaceName,
                currentInterface: selected.name,
                previousDownload: previousNetwork.downloadBytes,
                currentDownload: selected.downloadBytes,
                previousUpload: previousNetwork.uploadBytes,
                currentUpload: selected.uploadBytes,
                previousTime: previousNetwork.monotonicTime,
                currentTime: monotonicTime
            )
        } else {
            rates = (nil, nil)
        }

        previousNetwork = NetworkBaseline(
            interfaceName: selected.name,
            downloadBytes: selected.downloadBytes,
            uploadBytes: selected.uploadBytes,
            monotonicTime: monotonicTime
        )
        return (selected.name, rates.download, rates.upload)
    }

    private func interfaceCounters(errors: inout [String]) -> [InterfaceCounters] {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0 else {
            errors.append("네트워크 인터페이스를 읽지 못했습니다.")
            return []
        }
        defer { freeifaddrs(addressList) }

        // getifaddrs supplies the AF_LINK interface inventory and flags. On
        // macOS its legacy if_data byte fields are UInt32, so prefer the
        // 64-bit if_msghdr2 counters from NET_RT_IFLIST2 when available.
        let wideCounters = readWideInterfaceCounters(errors: &errors)
        var result: [String: InterfaceCounters] = [:]
        var cursor = addressList
        while let address = cursor {
            let value = address.pointee
            if value.ifa_addr?.pointee.sa_family == sa_family_t(AF_LINK),
               let interfaceNamePointer = value.ifa_name,
               let dataPointer = value.ifa_data {
                let name = String(cString: interfaceNamePointer)
                let flags = Int32(value.ifa_flags)
                if (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 {
                    let data = dataPointer.assumingMemoryBound(to: if_data.self).pointee
                    // getifaddrs can expose more than one address for an
                    // interface; retain one AF_LINK counter set, never sum it.
                    let counter = wideCounters?[name]
                    if result[name] == nil {
                        result[name] = InterfaceCounters(
                            name: name,
                            downloadBytes: counter?.download ?? UInt64(data.ifi_ibytes),
                            uploadBytes: counter?.upload ?? UInt64(data.ifi_obytes)
                        )
                    }
                }
            }
            cursor = value.ifa_next
        }
        return result.values.sorted { $0.name < $1.name }
    }

    private func readWideInterfaceCounters(
        errors: inout [String]
    ) -> [String: (download: UInt64, upload: UInt64)]? {
        var mib: [Int32] = [
            Int32(CTL_NET),
            Int32(PF_ROUTE),
            0,
            0,
            Int32(NET_RT_IFLIST2),
            0
        ]
        var byteCount = size_t(0)
        let sizeResult = mib.withUnsafeMutableBufferPointer {
            sysctl($0.baseAddress, u_int($0.count), nil, &byteCount, nil, 0)
        }
        guard sizeResult == 0, byteCount > 0 else {
            errors.append("64비트 네트워크 카운터를 읽지 못했습니다.")
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: byteCount)
        let readResult = bytes.withUnsafeMutableBytes { rawBuffer in
            mib.withUnsafeMutableBufferPointer {
                sysctl($0.baseAddress, u_int($0.count), rawBuffer.baseAddress, &byteCount, nil, 0)
            }
        }
        guard readResult == 0 else {
            errors.append("64비트 네트워크 카운터를 읽지 못했습니다.")
            return nil
        }

        var counters: [String: (download: UInt64, upload: UInt64)] = [:]
        var offset = 0
        while offset + MemoryLayout<if_msghdr2>.size <= bytes.count {
            let header: if_msghdr2 = bytes.withUnsafeBytes {
                $0.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
            }
            let messageLength = Int(header.ifm_msglen)
            guard messageLength > 0, offset + messageLength <= bytes.count else { break }
            if header.ifm_type == UInt8(RTM_IFINFO2) {
                var nameBuffer = [CChar](repeating: 0, count: Int(IFNAMSIZ))
                if if_indextoname(UInt32(header.ifm_index), &nameBuffer) != nil {
                    counters[String(cString: nameBuffer)] = (
                        UInt64(header.ifm_data.ifi_ibytes),
                        UInt64(header.ifm_data.ifi_obytes)
                    )
                }
            }
            offset += messageLength
        }
        return counters
    }

    private func selectInterface(
        from counters: [InterfaceCounters],
        errors: inout [String]
    ) -> InterfaceCounters? {
        guard !counters.isEmpty else {
            errors.append("사용 가능한 네트워크 인터페이스가 없습니다.")
            return nil
        }

        let preferred = primaryInterfaceName(errors: &errors)
        guard let preferred else {
            // No global IPv4/IPv6 route is normal while offline. Do not guess
            // an interface, because that would make a future VPN/physical
            // switch look like traffic on the wrong device.
            return nil
        }
        if let exact = counters.first(where: { $0.name == preferred }) {
            return exact
        }

        errors.append("기본 네트워크 인터페이스 \(preferred)의 카운터를 읽지 못했습니다.")
        return nil
    }

    private func primaryInterfaceName(errors: inout [String]) -> String? {
        guard let store = SCDynamicStoreCreate(nil, "MacPulse" as CFString, nil, nil) else {
            errors.append("기본 네트워크 인터페이스 설정을 읽지 못했습니다.")
            return nil
        }

        for key in ["State:/Network/Global/IPv4", "State:/Network/Global/IPv6"] {
            guard let value = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else {
                continue
            }
            if let name = value["PrimaryInterface"] as? String, !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private func readDisk(errors: inout [String]) -> (used: UInt64?, total: UInt64?) {
        let volumeURL = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)
        do {
            let values = try volumeURL.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityKey
            ])
            guard let total = values.volumeTotalCapacity, total > 0 else {
                errors.append("시동 디스크 전체 용량을 확인하지 못했습니다.")
                return (nil, nil)
            }
            guard let available = values.volumeAvailableCapacity, available >= 0 else {
                errors.append("시동 디스크 여유 용량을 확인하지 못했습니다.")
                return (nil, UInt64(total))
            }
            let totalBytes = UInt64(total)
            let availableBytes = min(UInt64(available), totalBytes)
            return (totalBytes - availableBytes, totalBytes)
        } catch {
            errors.append("시동 디스크 용량을 읽지 못했습니다: \(error.localizedDescription)")
            return (nil, nil)
        }
    }

    private func readBattery(errors: inout [String]) -> (percent: Double?, state: String) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return (nil, "배터리 없음")
        }
        guard let sourceListReference = IOPSCopyPowerSourcesList(info) else {
            return (nil, "배터리 없음")
        }
        let sourceList = sourceListReference.takeRetainedValue() as NSArray

        for source in sourceList {
            guard let description = IOPSGetPowerSourceDescription(info, source as CFTypeRef)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType as String,
                  description[kIOPSIsPresentKey as String] as? Bool != false else {
                continue
            }

            let current = (description[kIOPSCurrentCapacityKey as String] as? NSNumber)?.doubleValue
            let maximum = (description[kIOPSMaxCapacityKey as String] as? NSNumber)?.doubleValue
            let percent: Double?
            if let current, let maximum, maximum > 0 {
                percent = min(100, max(0, current / maximum * 100))
            } else {
                percent = nil
                errors.append("배터리 잔량을 확인하지 못했습니다.")
            }

            let powerState = description[kIOPSPowerSourceStateKey as String] as? String
            let charging = description[kIOPSIsChargingKey as String] as? Bool ?? false
            let state: String
            if powerState == kIOPSBatteryPowerValue as String {
                state = "배터리 사용"
            } else if charging {
                state = "충전 중"
            } else {
                state = "전원 연결"
            }
            return (percent, state)
        }
        return (nil, "배터리 없음")
    }
}
