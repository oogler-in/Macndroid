import SwiftUI

struct DeviceSidebar: View {
    @Environment(AppModel.self) private var app
    @State private var showingConnect = false

    var body: some View {
        @Bindable var app = app

        List(selection: $app.selectedSerial) {
            Section("Devices") {
                if app.devices.isEmpty {
                    Text("No devices connected")
                        .foregroundStyle(.secondary)
                }
                ForEach(app.devices) { device in
                    DeviceRow(device: device)
                        .tag(device.serial as String?)
                        .contextMenu { deviceMenu(device) }
                }
            }

            if let device = app.selectedDevice, device.state == .device {
                Section("Locations") {
                    ForEach(Place.all) { place in
                        Button {
                            app.requestNavigation(serial: device.serial, path: place.path)
                        } label: {
                            Label(place.title, systemImage: place.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                showingConnect = true
            } label: {
                Label("Connect via Wi‑Fi…", systemImage: "wifi")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(12)
        }
        .sheet(isPresented: $showingConnect) {
            ConnectSheet()
        }
    }

    @ViewBuilder
    private func deviceMenu(_ device: Device) -> some View {
        if device.isWireless {
            Button("Disconnect") { Task { await app.disconnect(device) } }
        } else if device.state == .device {
            Button("Switch to Wi‑Fi") { Task { await app.switchToWiFi(device) } }
        }
        Button("Copy Serial Number") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(device.serial, forType: .string)
        }
    }
}

private struct DeviceRow: View {
    let device: Device

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: device.iconName)
                .font(.title2)
                .foregroundStyle(device.state == .device ? Color.accentColor : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(device.subtitle)
                    .font(.caption)
                    .foregroundStyle(device.state == .unauthorized ? .orange : .secondary)
                if let total = device.details?.storageTotal, let free = device.details?.storageFree, total > 0 {
                    ProgressView(value: Double(total - free), total: Double(total))
                        .controlSize(.mini)
                    Text("\(ByteCountFormatter.string(fromByteCount: free, countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ConnectSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var pairAddress = ""
    @State private var pairCode = ""
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect via Wi‑Fi")
                .font(.title2.weight(.semibold))
            Text("On the device open **Developer options › Wireless debugging**. Your Mac and device must be on the same network.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("First time? Pair the device") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap **Pair device with pairing code** and enter what it shows.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("IP address & port, e.g. 192.168.1.20:37099", text: $pairAddress)
                        TextField("Pairing code", text: $pairCode)
                            .frame(width: 110)
                        Button("Pair") {
                            run { await app.pair(address: pairAddress, code: pairCode) }
                        }
                        .disabled(pairAddress.isEmpty || pairCode.isEmpty || working)
                    }
                }
                .padding(6)
            }

            GroupBox("Connect") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Use the **IP address & Port** shown on the Wireless debugging screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("IP address & port, e.g. 192.168.1.20:41235", text: $address)
                            .onSubmit(connect)
                        Button("Connect", action: connect)
                            .keyboardShortcut(.defaultAction)
                            .disabled(address.isEmpty || working)
                    }
                }
                .padding(6)
            }

            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(24)
        .frame(width: 540)
        .alert("Wi‑Fi", isPresented: Binding(
            get: { app.alertMessage != nil },
            set: { if !$0 { app.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.alertMessage ?? "")
        }
    }

    private func connect() {
        guard !address.isEmpty else { return }
        run {
            await app.connect(address: address)
            if app.alertMessage == nil { dismiss() }
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        working = true
        Task {
            await action()
            working = false
        }
    }
}
