import AppKit
import SwiftUI

struct StatusMenuContentView: View {
    let store: RateLimitStore
    let screenshotAppearance: ScreenshotAppearance?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex rate limit status")
                .font(.body.weight(.semibold))
                .foregroundStyle(palette.primaryText)

            if let staleMessage = store.staleMessage, !store.cards.isEmpty {
                Label(staleMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
            }

            if store.cards.isEmpty {
                Text(store.statusMessage)
                    .font(.body)
                    .foregroundStyle(palette.primaryText)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.cards.enumerated()), id: \.offset) { index, card in
                        RateLimitCardView(card: card, palette: palette)

                        if index < store.cards.count - 1 {
                            Divider()
                                .overlay(palette.divider)
                                .padding(.vertical, 14)
                        }
                    }
                }
            }

            Divider()
                .overlay(palette.divider)
            HStack(spacing: 8) {
                if let lastUpdated = store.lastUpdated, !store.cards.isEmpty {
                    Text(RateLimitFormatter.updatedFooterText(for: lastUpdated))
                        .font(.body)
                        .foregroundStyle(palette.primaryText)

                    if store.state == .connecting {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.75)
                    }
                }

                Spacer(minLength: 0)

                Text("v\(appVersion)")
                    .font(.body)
                    .foregroundStyle(palette.secondaryText)
            }
        }
        .padding(16)
        .frame(width: 352, alignment: .leading)
        .background {
            if let surface = palette.surface {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(surface)
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(palette.border, lineWidth: 1)
                    }
            }
        }
    }

    private var appVersion: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }

        return "0.1.1"
    }

    private var palette: StatusMenuPalette {
        StatusMenuPalette.forScreenshotAppearance(screenshotAppearance)
    }
}

private struct RateLimitCardView: View {
    let card: RateLimitCardViewData
    let palette: StatusMenuPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let statusMessage = card.statusMessage {
                Label(statusMessage, systemImage: statusIcon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
            }

            Text(card.title)
                .font(.body.weight(card.isPrimary ? .semibold : .regular))
                .foregroundStyle(palette.primaryText)

            RateLimitProgressBar(card: card, palette: palette)
                .padding(.top, 1)

            Text(card.usageText)
                .font(.body)
                .foregroundStyle(palette.primaryText)

            Text(card.combinedResetText)
                .font(.body)
                .foregroundStyle(palette.primaryText)

            if card.progressState == .exhausted {
                Text("Requests will resume when window resets.")
                    .font(.body)
                    .foregroundStyle(palette.primaryText)
            }
        }
        .padding(.vertical, card.isPrimary ? 2 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.accessibilityLabel)
    }

    private var statusIcon: String {
        switch card.progressState {
        case .normal:
            return "chart.bar"
        case .warning, .critical:
            return "exclamationmark.triangle.fill"
        case .exhausted:
            return "xmark.octagon.fill"
        }
    }
}

private struct RateLimitProgressBar: View {
    let card: RateLimitCardViewData
    let palette: StatusMenuPalette

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width * CGFloat(card.remainingPercent) / 100, card.remainingPercent > 0 ? 8 : 0)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(palette.progressTrack)

                Capsule(style: .continuous)
                    .fill(fillColor)
                    .frame(width: min(width, geometry.size.width))
            }
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        switch card.progressState {
        case .normal:
            return palette.normalFill
        case .warning:
            return palette.warningFill
        case .critical, .exhausted:
            return palette.criticalFill
        }
    }
}

private struct StatusMenuPalette {
    let surface: Color?
    let border: Color
    let primaryText: Color
    let secondaryText: Color
    let divider: Color
    let progressTrack: Color
    let normalFill: Color
    let warningFill: Color
    let criticalFill: Color

    static func forScreenshotAppearance(_ appearance: ScreenshotAppearance?) -> StatusMenuPalette {
        switch appearance {
        case .light:
            return StatusMenuPalette(
                surface: Color(nsColor: NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1.0)),
                border: Color(nsColor: NSColor(red: 0.79, green: 0.80, blue: 0.84, alpha: 1.0)),
                primaryText: Color(nsColor: NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1.0)),
                secondaryText: Color(nsColor: NSColor(red: 0.40, green: 0.41, blue: 0.46, alpha: 1.0)),
                divider: Color(nsColor: NSColor(red: 0.79, green: 0.80, blue: 0.84, alpha: 1.0)),
                progressTrack: Color(nsColor: NSColor(red: 0.78, green: 0.79, blue: 0.82, alpha: 1.0)),
                normalFill: Color(nsColor: NSColor(red: 0.27, green: 0.27, blue: 0.29, alpha: 1.0)),
                warningFill: Color(nsColor: .systemOrange),
                criticalFill: Color(nsColor: .systemRed)
            )
        case .dark:
            return StatusMenuPalette(
                surface: Color(nsColor: NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1.0)),
                border: Color(nsColor: NSColor(red: 0.26, green: 0.29, blue: 0.34, alpha: 1.0)),
                primaryText: Color(nsColor: NSColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1.0)),
                secondaryText: Color(nsColor: NSColor(red: 0.63, green: 0.66, blue: 0.72, alpha: 1.0)),
                divider: Color(nsColor: NSColor(red: 0.26, green: 0.29, blue: 0.34, alpha: 1.0)),
                progressTrack: Color(nsColor: NSColor(red: 0.26, green: 0.29, blue: 0.34, alpha: 1.0)),
                normalFill: Color(nsColor: NSColor(red: 0.86, green: 0.89, blue: 0.93, alpha: 1.0)),
                warningFill: Color(nsColor: .systemOrange),
                criticalFill: Color(nsColor: .systemRed)
            )
        case nil:
            return StatusMenuPalette(
                surface: nil,
                border: .clear,
                primaryText: Color(nsColor: .labelColor),
                secondaryText: Color(nsColor: .secondaryLabelColor),
                divider: Color(nsColor: .separatorColor),
                progressTrack: Color(nsColor: .quaternaryLabelColor),
                normalFill: Color(nsColor: .labelColor),
                warningFill: Color(nsColor: .systemOrange),
                criticalFill: Color(nsColor: .systemRed)
            )
        }
    }
}
