import Network

struct PathSnapshot: Equatable, Sendable {
    let isSatisfied: Bool
    let interface: NWInterface.InterfaceType?
}

protocol NetworkPathMonitoring: AnyObject {
    var pathUpdateHandler: (@Sendable (PathSnapshot) -> Void)? { get set }

    func start(queue: DispatchQueue)

    func cancel()
}

final class RealPathMonitor: NetworkPathMonitoring, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    var pathUpdateHandler: (@Sendable (PathSnapshot) -> Void)?

    func start(queue: DispatchQueue) {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.pathUpdateHandler?(Self.snapshot(from: path))
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }

    private static func snapshot(from path: NWPath) -> PathSnapshot {
        let interface: NWInterface.InterfaceType?
        if path.usesInterfaceType(.wifi) {
            interface = .wifi
        } else if path.usesInterfaceType(.cellular) {
            interface = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            interface = .wiredEthernet
        } else {
            interface = path.availableInterfaces.first?.type
        }

        return PathSnapshot(isSatisfied: path.status == .satisfied, interface: interface)
    }
}
