import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationSplitView {
            DeviceSidebar()
                .navigationSplitViewColumnWidth(min: 230, ideal: 260, max: 340)
        } detail: {
            VStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !app.transfers.isEmpty {
                    Divider()
                    TransferPanel()
                }
            }
        }
        .task { app.start() }
        .alert("Macndroid", isPresented: Binding(
            get: { app.alertMessage != nil },
            set: { if !$0 { app.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let adb = app.adb {
            if let device = app.selectedDevice {
                switch device.state {
                case .device:
                    FileBrowserView(device: device, adb: adb)
                        .id(device.serial)
                case .unauthorized, .authorizing:
                    UnauthorizedView()
                default:
                    ContentUnavailableView(
                        "\(device.displayName) is \(device.state.rawValue)",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Try unplugging and reconnecting the cable.")
                    )
                }
            } else if app.hasPolledOnce {
                NoDeviceView()
            } else {
                ProgressView("Looking for devices…")
            }
        } else {
            MissingADBView()
        }
    }
}
