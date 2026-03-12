import AppKit
import SwiftUI

struct StatusMenuContentView: View {
    @Environment(\.colorScheme) private var colorScheme

    let store: RateLimitStore
    let screenshotAppearance: ScreenshotAppearance?
    let showsOpenCodexButton: Bool
    let openCodexAction: (() -> Void)?

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
                if showsOpenCodexButton {
                    FooterActionButton(title: "Open Codex", palette: palette) {
                        openCodexAction?()
                    }
                }

                Spacer(minLength: 0)

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

    private var palette: StatusMenuPalette {
        StatusMenuPalette.forAppearance(screenshotAppearance, colorScheme: colorScheme)
    }
}

private struct FooterActionButton: View {
    let title: String
    let palette: StatusMenuPalette
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(FooterActionButtonStyle(palette: palette, isHovering: isHovering))
        .onHover { hovering in
            isHovering = hovering
        }
        .onDisappear {
            isHovering = false
        }
    }
}

private struct FooterActionButtonStyle: ButtonStyle {
    let palette: StatusMenuPalette
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(palette.actionText)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(palette.actionHighlight)
                    .opacity(isHovering || configuration.isPressed ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: isHovering || configuration.isPressed)
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

struct StatusMenuPalette {
    let surfaceColor: NSColor?
    let borderColor: NSColor
    let primaryTextColor: NSColor
    let secondaryTextColor: NSColor
    let dividerColor: NSColor
    let progressTrackColor: NSColor
    let normalFillColor: NSColor
    let warningFillColor: NSColor
    let criticalFillColor: NSColor
    let actionTextColor: NSColor
    let actionHighlightColor: NSColor

    var surface: Color? {
        surfaceColor.map { Color(nsColor: $0) }
    }

    var border: Color {
        Color(nsColor: borderColor)
    }

    var primaryText: Color {
        Color(nsColor: primaryTextColor)
    }

    var secondaryText: Color {
        Color(nsColor: secondaryTextColor)
    }

    var divider: Color {
        Color(nsColor: dividerColor)
    }

    var progressTrack: Color {
        Color(nsColor: progressTrackColor)
    }

    var normalFill: Color {
        Color(nsColor: normalFillColor)
    }

    var warningFill: Color {
        Color(nsColor: warningFillColor)
    }

    var criticalFill: Color {
        Color(nsColor: criticalFillColor)
    }

    var actionText: Color {
        Color(nsColor: actionTextColor)
    }

    var actionHighlight: Color {
        Color(nsColor: actionHighlightColor)
    }

    static func forAppearance(_ appearance: ScreenshotAppearance?, colorScheme: ColorScheme) -> StatusMenuPalette {
        switch appearance {
        case .light:
            return StatusMenuPalette(
                surfaceColor: NSColor(red: 0.95, green: 0.95, blue: 0.96, alpha: 1.0),
                borderColor: NSColor(red: 0.79, green: 0.80, blue: 0.84, alpha: 1.0),
                primaryTextColor: NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1.0),
                secondaryTextColor: NSColor(red: 0.40, green: 0.41, blue: 0.46, alpha: 1.0),
                dividerColor: NSColor(red: 0.79, green: 0.80, blue: 0.84, alpha: 1.0),
                progressTrackColor: NSColor(red: 0.78, green: 0.79, blue: 0.82, alpha: 1.0),
                normalFillColor: NSColor(red: 0.27, green: 0.27, blue: 0.29, alpha: 1.0),
                warningFillColor: .systemOrange,
                criticalFillColor: .systemRed,
                actionTextColor: NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1.0),
                actionHighlightColor: NSColor(red: 0.79, green: 0.80, blue: 0.84, alpha: 0.28)
            )
        case .dark:
            return StatusMenuPalette(
                surfaceColor: NSColor(red: 0.10, green: 0.12, blue: 0.15, alpha: 1.0),
                borderColor: NSColor(red: 0.26, green: 0.29, blue: 0.34, alpha: 1.0),
                primaryTextColor: NSColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1.0),
                secondaryTextColor: NSColor(red: 0.63, green: 0.66, blue: 0.72, alpha: 1.0),
                dividerColor: NSColor(red: 0.26, green: 0.29, blue: 0.34, alpha: 1.0),
                progressTrackColor: NSColor(red: 0.26, green: 0.29, blue: 0.34, alpha: 1.0),
                normalFillColor: NSColor(red: 0.86, green: 0.89, blue: 0.93, alpha: 1.0),
                warningFillColor: .systemOrange,
                criticalFillColor: .systemRed,
                actionTextColor: NSColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1.0),
                actionHighlightColor: NSColor(red: 0.26, green: 0.29, blue: 0.34, alpha: 0.90)
            )
        case nil:
            return StatusMenuPalette(
                surfaceColor: nil,
                borderColor: .clear,
                primaryTextColor: .labelColor,
                secondaryTextColor: .secondaryLabelColor,
                dividerColor: .separatorColor,
                progressTrackColor: .quaternaryLabelColor,
                normalFillColor: .labelColor,
                warningFillColor: .systemOrange,
                criticalFillColor: .systemRed,
                actionTextColor: .labelColor,
                actionHighlightColor: liveActionHighlightColor(for: colorScheme)
            )
        }
    }

    private static func liveActionHighlightColor(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(white: 1.0, alpha: 0.12)
        default:
            return NSColor(white: 0.0, alpha: 0.12)
        }
    }
}
