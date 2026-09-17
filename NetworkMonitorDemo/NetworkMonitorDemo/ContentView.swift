import SwiftUI
import NetworkMonitorKit

struct ContentView: View {
    @State  private  var status: NetworkStatus = .unknown

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: status.symbolName)
                .font(.system(size: 64))
                .foregroundStyle(status == .offline ? .red : .green)

            Text(status.displayName)
                .font(.title2)
                .bold()
        }
        .padding()
        .onAppear {
            NetworkMonitor.shared.onStatusChanged {  newStatus in
                Task {@MainActor in
                    status = newStatus

                }
            }
            NetworkMonitor.shared.start()
            status = NetworkMonitor.shared.status
        }
    }
}

#Preview {
    ContentView()
}
