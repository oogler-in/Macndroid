import AppKit
import SwiftUI

struct TransferPanel: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Transfers")
                    .font(.headline)
                let active = app.transfers.filter { !$0.status.isFinished }.count
                if active > 0 {
                    Text("\(active) in progress")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear Finished") { app.clearFinished() }
                    .buttonStyle(.link)
                    .disabled(!app.transfers.contains { $0.status.isFinished })
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(app.transfers.reversed()) { item in
                        TransferRow(item: item)
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .frame(maxHeight: 170)
        }
        .background(.background.secondary)
    }
}

private struct TransferRow: View {
    @Environment(AppModel.self) private var app
    let item: TransferItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.status == .running {
                    if let fraction = item.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                }
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if !item.status.isFinished {
                Button { app.cancel(item) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Cancel")
            } else if item.status == .completed, item.kind == .download {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.targetPath)])
                } label: { Image(systemName: "magnifyingglass.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Show in Finder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var icon: String {
        switch item.kind {
        case .upload: return "arrow.up.circle.fill"
        case .download: return "arrow.down.circle.fill"
        case .install: return "shippingbox.circle.fill"
        }
    }

    private var iconColor: Color {
        switch item.status {
        case .failed: return .red
        case .cancelled: return .secondary
        case .completed: return .green
        default: return .accentColor
        }
    }

    private var statusColor: Color {
        if case .failed = item.status { return .red }
        return .secondary
    }

    private var verb: String {
        switch item.kind {
        case .upload: return "Copied to device"
        case .download: return item.openWhenDone ? "Opened" : "Saved to Mac"
        case .install: return "Installed"
        }
    }

    private var statusText: String {
        let fmt: (Int64) -> String = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        switch item.status {
        case .queued:
            return "Waiting…"
        case .running:
            if item.kind == .install { return "Installing…" }
            var text = ""
            if let total = item.totalBytes {
                text = "\(fmt(item.transferredBytes)) of \(fmt(total))"
            } else {
                text = item.isDirectory ? "Copying folder…" : "Copying…"
            }
            if let speed = item.bytesPerSecond, item.totalBytes != nil {
                text += " — \(fmt(Int64(speed)))/s"
            }
            return text
        case .completed:
            var text = verb
            if let total = item.totalBytes, item.kind != .install { text += " · \(fmt(total))" }
            if let speed = item.bytesPerSecond, item.kind != .install, item.totalBytes != nil {
                text += " · \(fmt(Int64(speed)))/s"
            }
            return text
        case .failed(let message):
            return "Failed: \(message)"
        case .cancelled:
            return "Cancelled"
        }
    }
}
