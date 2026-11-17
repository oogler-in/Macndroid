import SwiftUI

private struct StepList: View {
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Color.accentColor.opacity(0.18)))
                    Text(.init(step))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
    }
}

struct NoDeviceView: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "cable.connector")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Connect your Android phone or tablet")
                .font(.title2.weight(.semibold))
            StepList(steps: [
                "On the device, open **Settings › About phone** and tap **Build number** 7 times to unlock Developer options.",
                "Open **Settings › System › Developer options** and turn on **USB debugging**.",
                "Connect the device to this Mac with a USB cable.",
                "Tap **Allow** on the “Allow USB debugging?” prompt on the device.",
            ])
            Text("Already set up wireless debugging? Use **Connect via Wi‑Fi** in the sidebar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
    }
}

struct UnauthorizedView: View {
    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "lock.iphone")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.orange)
            Text("Allow access on your device")
                .font(.title2.weight(.semibold))
            StepList(steps: [
                "Unlock your phone or tablet.",
                "Tap **Allow** on the “Allow USB debugging?” prompt. Tick **Always allow from this computer** to skip this next time.",
                "No prompt? Unplug and reconnect the cable, or choose **Revoke USB debugging authorizations** in Developer options and try again.",
            ])
        }
        .padding(40)
    }
}

struct MissingADBView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Android Platform Tools not found")
                .font(.title2.weight(.semibold))
            Text("Macndroid uses Google's `adb` tool to talk to your device. Install it with Homebrew:")
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Text("brew install android-platform-tools")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
            Text("Or install Android Studio, which puts it in ~/Library/Android/sdk/platform-tools.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Try Again") { app.retryLocatingADB() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
    }
}
