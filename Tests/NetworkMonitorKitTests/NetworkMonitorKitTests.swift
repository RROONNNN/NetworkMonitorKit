import XCTest
import Network

@testable import NetworkMonitorKit

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _value
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _value = newValue
        }
    }
}

private final class FakeNetworkPathMonitor: NetworkPathMonitoring {
    var pathUpdateHandler: (@Sendable (PathSnapshot) -> Void)?
    let startCallCount = Locked<Int>(0)
    let cancelCallCount = Locked<Int>(0)

    func start(queue: DispatchQueue) {
        startCallCount.value += 1
    }

    func cancel() {
        cancelCallCount.value += 1
    }

    func simulate(_ snapshot: PathSnapshot) {
        pathUpdateHandler?(snapshot)
    }
}

final class NetworkMonitorKitTests: XCTestCase {

    // MARK: - NetworkStatus.displayName

    func test_displayName_returnsHumanReadableString() {
        XCTAssertEqual(NetworkStatus.wifi.displayName, "Wi-Fi")
        XCTAssertEqual(NetworkStatus.cellular.displayName, "Cellular")
        XCTAssertEqual(NetworkStatus.ethernet.displayName, "Ethernet")
        XCTAssertEqual(NetworkStatus.other.displayName, "Other")
        XCTAssertEqual(NetworkStatus.offline.displayName, "Offline")
        XCTAssertEqual(NetworkStatus.unknown.displayName, "Unknown")
    }

    // MARK: - NetworkStatus.symbolName

    func test_symbolName_returnsSFSymbolName() {
        XCTAssertEqual(NetworkStatus.wifi.symbolName, "wifi")
        XCTAssertEqual(NetworkStatus.cellular.symbolName, "antenna.radiowaves.left.and.right")
        XCTAssertEqual(NetworkStatus.ethernet.symbolName, "network")
        XCTAssertEqual(NetworkStatus.other.symbolName, "network")
        XCTAssertEqual(NetworkStatus.offline.symbolName, "wifi.slash")
        XCTAssertEqual(NetworkStatus.unknown.symbolName, "questionmark.circle")
    }

    // MARK: - NetworkMonitor

    private func makeSUT() -> (sut: NetworkMonitor, monitor: FakeNetworkPathMonitor) {
        let fake = FakeNetworkPathMonitor()
        let sut = NetworkMonitor(
            monitor: fake,
            stateQueue: DispatchQueue(label: "com.example.NetworkMonitorKitTests.state"),
            callbackQueue: DispatchQueue(label: "com.example.NetworkMonitorKitTests.callback")
        )
        return (sut, fake)
    }

    func test_shared_returnsSameInstance() {
        XCTAssertTrue(NetworkMonitor.shared === NetworkMonitor.shared)
    }

    func test_status_isUnknownBeforeAnyUpdate() {
        let (sut, _) = makeSUT()

        XCTAssertEqual(sut.status, .unknown)
    }

    // MARK: - start() / stop() delegate to the underlying monitor

    func test_start_startsUnderlyingMonitor() {
        let (sut, fake) = makeSUT()

        sut.start()
        flush(sut, using: fake)

        XCTAssertEqual(fake.startCallCount.value, 1)
    }

    func test_start_calledTwice_startsUnderlyingMonitorOnlyOnce() {
        let (sut, fake) = makeSUT()

        sut.start()
        sut.start()
        flush(sut, using: fake)

        XCTAssertEqual(fake.startCallCount.value, 1)
    }

    func test_stop_cancelsUnderlyingMonitor() {
        let (sut, fake) = makeSUT()

        sut.start()
        sut.stop()
        flush(sut, using: fake)

        XCTAssertEqual(fake.cancelCallCount.value, 1)
    }

    // MARK: - PathSnapshot -> NetworkStatus mapping

    func test_wifiSnapshot_mapsToWifiStatus() {
        assertStatus(for: PathSnapshot(isSatisfied: true, interface: .wifi), equals: .wifi)
    }

    func test_cellularSnapshot_mapsToCellularStatus() {
        assertStatus(for: PathSnapshot(isSatisfied: true, interface: .cellular), equals: .cellular)
    }

    func test_wiredEthernetSnapshot_mapsToEthernetStatus() {
        assertStatus(for: PathSnapshot(isSatisfied: true, interface: .wiredEthernet), equals: .ethernet)
    }

    func test_otherSatisfiedSnapshot_mapsToOtherStatus() {
        assertStatus(for: PathSnapshot(isSatisfied: true, interface: .other), equals: .other)
    }

    func test_unsatisfiedSnapshot_mapsToOfflineStatus() {
        assertStatus(for: PathSnapshot(isSatisfied: false, interface: nil), equals: .offline)
    }

    // MARK: - Listener behavior

    func test_duplicateStatus_doesNotNotifyListenerAgain() {
        let (sut, fake) = makeSUT()
        let callCount = Locked<Int>(0)
        let firstUpdate = expectation(description: "first distinct update")
        let secondUpdate = expectation(description: "second distinct update")

        sut.onStatusChanged { _ in
            callCount.value += 1
            if callCount.value == 1 { firstUpdate.fulfill() }
            if callCount.value == 2 { secondUpdate.fulfill() }
        }

        fake.simulate(PathSnapshot(isSatisfied: true, interface: .wifi))
        wait(for: [firstUpdate], timeout: 1)

        fake.simulate(PathSnapshot(isSatisfied: true, interface: .wifi)) // duplicate, must be ignored
        fake.simulate(PathSnapshot(isSatisfied: true, interface: .cellular)) // distinct, must notify
        wait(for: [secondUpdate], timeout: 1)

        XCTAssertEqual(callCount.value, 2)
    }

    func test_removeListener_stopsFurtherNotifications() {
        let (sut, fake) = makeSUT()
        let callCount = Locked<Int>(0)
        let firstUpdate = expectation(description: "first update")

        let id = sut.onStatusChanged { _ in
            callCount.value += 1
            firstUpdate.fulfill()
        }

        fake.simulate(PathSnapshot(isSatisfied: true, interface: .wifi))
        wait(for: [firstUpdate], timeout: 1)

        sut.removeListener(id)

        // A second listener proves the queue has processed the next status
        // change, without relying on an arbitrary sleep.
        let confirmUpdate = expectation(description: "queue processed the next change")
        sut.onStatusChanged { _ in confirmUpdate.fulfill() }
        fake.simulate(PathSnapshot(isSatisfied: false, interface: nil))
        wait(for: [confirmUpdate], timeout: 1)

        XCTAssertEqual(callCount.value, 1)
    }

    func test_removeListener_withUnknownId_doesNotCrash() {
        let (sut, _) = makeSUT()

        sut.removeListener(UUID())
    }

    // MARK: - Helpers

    /// Blocks until every block already enqueued on `sut`'s internal serial
    /// queue has run, by riding the same FIFO ordering guarantee: this
    /// listener + simulate pair is submitted after everything above it, so
    /// it can only fire once the queue has drained up to that point.
    private func flush(_ sut: NetworkMonitor, using fake: FakeNetworkPathMonitor) {
        let settled = expectation(description: "queue flushed")
        sut.onStatusChanged { _ in settled.fulfill() }
        fake.simulate(PathSnapshot(isSatisfied: true, interface: .other))
        wait(for: [settled], timeout: 1)
    }

    private func assertStatus(
        for snapshot: PathSnapshot,
        equals expected: NetworkStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (sut, fake) = makeSUT()
        let receivedUpdate = expectation(description: "status update")
        let receivedStatus = Locked<NetworkStatus?>(nil)

        sut.onStatusChanged { status in
            receivedStatus.value = status
            receivedUpdate.fulfill()
        }

        sut.start()
        fake.simulate(snapshot)

        wait(for: [receivedUpdate], timeout: 1)

        XCTAssertEqual(receivedStatus.value, expected, file: file, line: line)
    }
}
