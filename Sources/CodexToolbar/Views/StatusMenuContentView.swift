import SwiftUI

struct StatusMenuContentView: View {
    let store: RateLimitStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Codex rate limit status")
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)

            if let staleMessage = store.staleMessage, !store.cards.isEmpty {
                Label(staleMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            if store.cards.isEmpty {
                Text(store.statusMessage)
                    .font(.body)
                    .foregroundStyle(.primary)
                if let debugDetail = store.debugDetail {
                    Text(debugDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.cards.enumerated()), id: \.offset) { index, card in
                        RateLimitCardView(card: card)

                        if index < store.cards.count - 1 {
                            Divider()
                                .padding(.vertical, 14)
                        }
                    }
                }
            }

            if let debugDetail = store.debugDetail, !store.cards.isEmpty, store.state != .ready {
                Text(debugDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastUpdated = store.lastUpdated, !store.cards.isEmpty {
                Divider()
                Text(RateLimitFormatter.updatedFooterText(for: lastUpdated))
                    .font(.body)
                    .foregroundStyle(.primary)
            }
        }
        .padding(16)
        .frame(width: 352, alignment: .leading)
    }
}

private struct RateLimitCardView: View {
    let card: RateLimitCardViewData

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let statusMessage = card.statusMessage {
                Label(statusMessage, systemImage: statusIcon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Text(card.title)
                .font(.body.weight(card.isPrimary ? .semibold : .regular))
                .foregroundStyle(.primary)

            RateLimitProgressBar(card: card)
                .padding(.top, 1)

            Text(card.usageText)
                .font(.body)
                .foregroundStyle(.primary)

            Text(card.combinedResetText)
                .font(.body)
                .foregroundStyle(.primary)

            if card.progressState == .exhausted {
                Text("Requests will resume when window resets.")
                    .font(.body)
                    .foregroundStyle(.primary)
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

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width * CGFloat(card.remainingPercent) / 100, card.remainingPercent > 0 ? 8 : 0)

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(nsColor: .quaternaryLabelColor))

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
            return Color(nsColor: .labelColor)
        case .warning:
            return Color(nsColor: .systemOrange)
        case .critical, .exhausted:
            return Color(nsColor: .systemRed)
        }
    }
}
