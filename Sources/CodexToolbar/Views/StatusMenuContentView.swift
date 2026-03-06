import SwiftUI

struct StatusMenuContentView: View {
    let store: RateLimitStore
    let loginItemController: LoginItemController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                CodexGlyphView()
                    .frame(width: 18, height: 18)

                Text("Rate limits remaining")
                    .font(.system(size: 17, weight: .semibold))
            }

            if store.rows.isEmpty {
                Text(store.statusMessage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(store.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 12) {
                            Text(row.label)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text(row.percentText)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.secondary)

                            Text(row.resetText)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 72, alignment: .trailing)
                        }
                    }
                }
            }

            Divider()

            if let lastUpdated = store.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Text(store.state == .connecting ? "Connecting…" : store.statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Button("Refresh now") {
                    Task {
                        await store.refreshNow()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))

                Toggle(isOn: Binding(
                    get: { loginItemController.isEnabled },
                    set: { loginItemController.setEnabled($0) }
                )) {
                    Text("Launch at login")
                        .font(.system(size: 13, weight: .medium))
                }
                .toggleStyle(.checkbox)

                if !loginItemController.statusMessage.isEmpty {
                    Text(loginItemController.statusMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(16)
        .frame(width: 300, alignment: .leading)
    }
}

struct StatusBarLabelView: View {
    let store: RateLimitStore

    var body: some View {
        HStack(spacing: 6) {
            CodexGlyphView()
                .frame(width: 14, height: 14)
            Text(store.statusBarText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
    }
}

struct CodexGlyphView: View {
    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.12, to: 0.94)
                .stroke(style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotation(.degrees(-120))

            Capsule(style: .continuous)
                .fill(.primary)
                .frame(width: 6, height: 2)
                .offset(x: 2.2, y: -2.5)
                .rotationEffect(.degrees(18))
        }
        .foregroundStyle(.primary)
    }
}
