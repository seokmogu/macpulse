import XCTest
@testable import MacPulseCore

final class MetricCalculationsTests: XCTestCase {
    func testCPUUsesNilBaselineAndHandlesUInt32Wrap() {
        let initial = MetricCalculations.CPUCounterSnapshot(
            user: 10,
            system: 20,
            nice: 30,
            idle: UInt32.max - 1
        )
        let afterWrap = MetricCalculations.CPUCounterSnapshot(
            user: 11,
            system: 20,
            nice: 30,
            idle: 1
        )

        XCTAssertNil(MetricCalculations.cpuPercent(previous: nil, current: initial))
        // The idle counter wrapped from UInt32.max - 1 to 1: its delta is
        // three ticks, yielding one busy tick out of four (25%).
        let value = MetricCalculations.cpuPercent(previous: initial, current: afterWrap)
        XCTAssertEqual(value ?? -1, 25, accuracy: 0.0001)
    }

    func testCounterResetAndInterfaceChangeInvalidateRates() {
        XCTAssertEqual(
            MetricCalculations.counterRate(
                previous: 1_000,
                current: 1_500,
                previousTime: 10,
                currentTime: 11
            ),
            500
        )
        XCTAssertNil(
            MetricCalculations.counterRate(
                previous: 1_500,
                current: 1_000,
                previousTime: 11,
                currentTime: 12
            )
        )

        let changed = MetricCalculations.networkRates(
            previousInterface: "en0",
            currentInterface: "en1",
            previousDownload: 1_000,
            currentDownload: 2_000,
            previousUpload: 100,
            currentUpload: 200,
            previousTime: 10,
            currentTime: 11
        )
        XCTAssertNil(changed.download)
        XCTAssertNil(changed.upload)
    }

    func testMemoryCalculationClampsUnderflowAndPhysicalLimit() {
        XCTAssertEqual(
            MetricCalculations.memoryUsedBytes(
                activePages: 1,
                inactivePages: 2,
                wiredPages: 3,
                compressorPages: 4,
                purgeablePages: 100,
                externalPages: 100,
                pageSize: 4_096,
                physicalMemoryBytes: 1_024 * 1_024
            ),
            0
        )
        XCTAssertEqual(
            MetricCalculations.memoryUsedBytes(
                activePages: 1_000,
                inactivePages: 1_000,
                wiredPages: 1_000,
                compressorPages: 1_000,
                purgeablePages: 0,
                externalPages: 0,
                pageSize: 4_096,
                physicalMemoryBytes: 4_096
            ),
            4_096
        )
    }
}
