import Foundation

struct DeviceDetails: Hashable {
    var manufacturer: String?
    var model: String?
    var androidVersion: String?
    var isTablet = false
    var storageTotal: Int64?
    var storageFree: Int64?
}

struct Device: Identifiable, Hashable {
    enum State: String {
        case device, unauthorized, offline, recovery, sideload, bootloader, authorizing, unknown
    }

    let serial: String
    var state: State
    var listModel: String?
    var details: DeviceDetails?

    var id: String { serial }

    var isWireless: Bool {
        serial.contains(":") || serial.contains("_adb-tls-connect")
    }

    var displayName: String {
        let model = details?.model ?? listModel
        if let model, !model.isEmpty {
            if let maker = details?.manufacturer, !maker.isEmpty,
               !model.lowercased().hasPrefix(maker.lowercased()) {
                return "\(maker.capitalized) \(model)"
            }
            return model
        }
        return serial
    }

    var iconName: String {
        details?.isTablet == true ? "ipad.landscape" : "candybarphone"
    }

    var subtitle: String {
        switch state {
        case .device:
            var parts: [String] = []
            if let version = details?.androidVersion { parts.append("Android \(version)") }
            parts.append(isWireless ? "Wi‑Fi" : "USB")
            return parts.joined(separator: " · ")
        case .unauthorized: return "Waiting for permission"
        case .authorizing: return "Authorizing…"
        case .offline: return "Offline"
        default: return state.rawValue.capitalized
        }
    }

    /// Parses `adb devices -l` output.
    static func parseList(_ output: String) -> [Device] {
        output.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = String(rawLine)
            if line.hasPrefix("List of devices") || line.hasPrefix("*") { return nil }
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard parts.count >= 2 else { return nil }

            var info: [String: String] = [:]
            for part in parts.dropFirst(2) {
                if let colon = part.firstIndex(of: ":") {
                    info[String(part[..<colon])] = String(part[part.index(after: colon)...])
                }
            }
            return Device(
                serial: parts[0],
                state: State(rawValue: parts[1]) ?? .unknown,
                listModel: info["model"]?.replacingOccurrences(of: "_", with: " ")
            )
        }
    }
}

/// Quick-access folders on Android shared storage.
struct Place: Identifiable {
    let title: String
    let path: String
    let icon: String
    var id: String { path }

    static let all: [Place] = [
        Place(title: "Internal Storage", path: "/sdcard", icon: "internaldrive"),
        Place(title: "Download", path: "/sdcard/Download", icon: "arrow.down.circle"),
        Place(title: "Camera (DCIM)", path: "/sdcard/DCIM", icon: "camera"),
        Place(title: "Pictures", path: "/sdcard/Pictures", icon: "photo"),
        Place(title: "Movies", path: "/sdcard/Movies", icon: "film"),
        Place(title: "Music", path: "/sdcard/Music", icon: "music.note"),
        Place(title: "Documents", path: "/sdcard/Documents", icon: "doc.text"),
    ]
}
