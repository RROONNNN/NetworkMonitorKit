import Foundation
import Network

public final class NetworkMonitor: @unchecked Sendable {
    public static let shared = NetworkMonitor()
    private let monitor: NetworkPathMonitoring
    private let stateQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private var currentStatus: NetworkStatus = .unknown
    private var listeners:
        [UUID: @Sendable (NetworkStatus) -> Void] = [:]
    private var isRunning = false
    // MARK: - Public initializer

    public convenience init() {

          self.init(
              monitor: RealPathMonitor(),

              stateQueue: DispatchQueue(
                  label: "com.example.NetworkMonitorKit.state",
                  qos: .utility
              ),

              callbackQueue: DispatchQueue.main
          )
      }
    // MARK: - Internal initializer

       init(
           monitor: NetworkPathMonitoring,
           stateQueue: DispatchQueue,
           callbackQueue: DispatchQueue
       ) {

           self.monitor = monitor

           self.stateQueue = stateQueue

           self.callbackQueue = callbackQueue

           monitor.pathUpdateHandler = { [weak self] snapshot in

               self?.handle(snapshot: snapshot)
           }
       }
    // MARK: - Start

    public func start() {

        stateQueue.async { [weak self] in

            guard let self else {
                return
            }

            guard !self.isRunning else {
                return
            }

            self.isRunning = true

            self.monitor.start(
                queue: self.stateQueue
            )
        }
    }

    // MARK: - Stop

    public func stop() {

        stateQueue.async { [weak self] in

            guard let self else {
                return
            }

            guard self.isRunning else {
                return
            }

            self.isRunning = false

            self.monitor.cancel()
        }
    }

    // MARK: - Current status

    public var status: NetworkStatus {

        stateQueue.sync {
            currentStatus
        }
    }

    // MARK: - Listener

    @discardableResult
    public func onStatusChanged(
        _ handler: @escaping @Sendable (NetworkStatus) -> Void
    ) -> UUID {

        let id = UUID()

        stateQueue.async { [weak self] in

            self?.listeners[id] = handler
        }

        return id
    }

    // MARK: - Remove listener

    public func removeListener(
        _ id: UUID
    ) {

        stateQueue.async { [weak self] in

            self?.listeners.removeValue(
                forKey: id
            )
        }
    }

    // MARK: - Path handling

    private func handle(snapshot: PathSnapshot) {
        let status: NetworkStatus
        if snapshot.isSatisfied {
            switch snapshot.interface {
            case .wifi:
                status = .wifi
            case .cellular:
                status = .cellular
            case .wiredEthernet:
                status = .ethernet
            default:
                status = .other
            }
        } else {
            status = .offline
        }

        stateQueue.async { [weak self] in
            guard let self, self.currentStatus != status else { return }
            self.currentStatus = status

            let listeners = self.listeners.values
            self.callbackQueue.async {
                for listener in listeners {
                    listener(status)
                }
            }
        }
    }

}
