import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Typist Settings")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 8) {
                Text("Privacy")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))

                Text("• Typed text is never stored.")
                Text("• Only key usage counts, timestamps, and device class are persisted locally.")
                Text("• A 90-day raw event ring buffer is retained for aggregation integrity.")
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { appModel.launchAtLoginEnabled },
                    set: { appModel.setLaunchAtLogin($0) }
                )
            )

            if let launchError = appModel.launchErrorMessage {
                Text("Launch setting error: \(launchError)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.orange)
            }

            HStack {
                Button("Reset All Stats") {
                    Task {
                        await appModel.resetStats()
                    }
                }

                Spacer()

                Button("Close") {
                    NSApp.keyWindow?.close()
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(minWidth: 380, minHeight: 300)
    }
}
