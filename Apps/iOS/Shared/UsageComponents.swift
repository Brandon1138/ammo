import Foundation
import SwiftUI
import UsageKit
import WidgetKit

/// Thick rounded progress bar. `fraction` is how much ammo is LEFT (0…1).
struct CapsuleBar: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    var fraction: Double
    var color: Color
    var height: CGFloat = 7

    var body: some View {
        let clampedFraction = min(1, max(0, fraction))
        Canvas { context, size in
            guard size.width.isFinite, size.height.isFinite,
                  size.width > 0, size.height > 0 else { return }

            let radius = size.height / 2
            let track = Path(roundedRect: CGRect(origin: .zero, size: size),
                             cornerRadius: radius)
            context.fill(track, with: .color(.primary.opacity(0.18)))

            let fillWidth = size.width * clampedFraction
            if fillWidth > 0 {
                let fillRect = CGRect(x: 0, y: 0,
                                      width: fillWidth, height: size.height)
                let fill = Path(roundedRect: fillRect,
                                cornerRadius: min(radius, fillWidth / 2))
                context.fill(fill, with: .color(fillColor))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        renderingMode == .fullColor ? color : .primary
    }
}

/// One limit window: "Session ……… 98%" over a bar.
/// The percent stays primary-colored until the window runs low, then it
/// picks up the amber/red warning color along with the bar.
struct UsageWindowRow: View {
    let window: LimitWindow
    var font: Font = .footnote
    var barHeight: CGFloat = 7
    var spacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(font)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(window.remainingPercentText)
                    .font(font.weight(.semibold).monospacedDigit())
                    .foregroundStyle(window.isRunningLow ? window.barColor : .primary)
                    .widgetAccentable()
                    .fixedSize(horizontal: true, vertical: false)
            }
            CapsuleBar(fraction: window.remainingPercent / 100,
                       color: window.barColor,
                       height: barHeight)
        }
    }
}

/// A finite reset countdown string, recomputed whenever WidgetKit requests a
/// timeline. Keeping this as ordinary text makes snapshot layout deterministic.
struct ResetLine: View {
    let date: Date
    let referenceDate: Date
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.clockwise")
                .font(font.weight(.medium))
            Text("Resets in \(remainingText)")
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(.secondary)
    }

    private var remainingText: String {
        let seconds = max(0, Int(date.timeIntervalSince(referenceDate)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }
}

/// Conservative rollover presentation shared by the app and widgets. The last
/// fetched meter remains in place until a provider confirms the reset.
struct ResetStatusLine: View {
    let snapshot: UsageSnapshot
    let group: [LimitWindow]
    let referenceDate: Date
    var font: Font = .caption

    @ViewBuilder var body: some View {
        if let resetDate = group.compactMap(\.resetsAt).min() {
            if resetDate > referenceDate {
                ResetLine(date: resetDate, referenceDate: referenceDate, font: font)
            } else {
                status("Reset due", systemImage: "arrow.clockwise")
            }
        } else if snapshot.provider == .claude,
                  group.contains(where: { $0.kind == .session && $0.usedPercent <= 0.001 }) {
            status("Not started", systemImage: "pause.circle")
        }
    }

    private func status(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(font)
            .lineLimit(1)
            .foregroundStyle(.secondary)
    }
}

/// A calm, compact alternative to rendering raw network or decoding errors.
/// Technical details stay in private logs; this component receives only a
/// stable failure category and copy written for the person using the app.
struct InlineStatusNotice: View {
    let title: String
    let message: String
    let systemImage: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(.footnote.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.primary)
                        .padding(.top, 3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: action == nil ? .combine : .contain)
    }
}

struct RefreshIssueNotice: View {
    let providerName: String
    let failure: UsageFailureKind
    let hasCachedSnapshot: Bool
    var retry: (() -> Void)?

    var body: some View {
        InlineStatusNotice(
            title: failure.refreshTitle,
            message: failure.refreshMessage(providerName: providerName,
                                            hasCachedSnapshot: hasCachedSnapshot),
            systemImage: failure.systemImage,
            actionTitle: failure.canRetryImmediately ? "Try Again" : nil,
            action: failure.canRetryImmediately ? retry : nil)
    }
}

struct SignInIssueNotice: View {
    let providerName: String
    let failure: UsageFailureKind

    var body: some View {
        InlineStatusNotice(
            title: "Couldn't sign in",
            message: failure.signInMessage(providerName: providerName),
            systemImage: failure.systemImage)
    }
}

private extension UsageFailureKind {
    var systemImage: String {
        switch self {
        case .timedOut: "clock.badge.exclamationmark"
        case .rateLimited: "pause.circle"
        case .offline: "wifi.slash"
        case .authentication: "person.crop.circle.badge.exclamationmark"
        case .serviceUnavailable, .invalidResponse, .unavailable, .unknown:
            "exclamationmark.circle"
        }
    }

    var canRetryImmediately: Bool {
        switch self {
        case .timedOut, .offline, .serviceUnavailable, .invalidResponse, .unknown: true
        case .rateLimited, .authentication, .unavailable: false
        }
    }

    var refreshTitle: String {
        switch self {
        case .timedOut: "Update took too long"
        case .rateLimited: "Taking a short break"
        case .offline: "You're offline"
        case .authentication: "Sign-in needs attention"
        case .serviceUnavailable: "Service temporarily unavailable"
        case .invalidResponse: "Update unavailable"
        case .unavailable: "Not available yet"
        case .unknown: "Couldn't refresh"
        }
    }

    func refreshMessage(providerName: String, hasCachedSnapshot: Bool) -> String {
        let cached = hasCachedSnapshot ? " Your last update is still shown." : ""
        switch self {
        case .timedOut:
            return "\(providerName) didn't respond in time.\(cached)"
        case .rateLimited:
            return "\(providerName) asked Ammo to slow down. We'll try again automatically.\(cached)"
        case .offline:
            return "Ammo will update \(providerName) when your connection is back.\(cached)"
        case .authentication:
            return "Remove and add this \(providerName) account again to resume updates.\(cached)"
        case .serviceUnavailable:
            return "\(providerName) can't be reached right now. Try again in a moment.\(cached)"
        case .invalidResponse:
            return "\(providerName) returned something Ammo couldn't read. Try again shortly.\(cached)"
        case .unavailable:
            return "Support for \(providerName) isn't ready in this build."
        case .unknown:
            return "Something interrupted the \(providerName) update. Try again in a moment.\(cached)"
        }
    }

    func signInMessage(providerName: String) -> String {
        switch self {
        case .timedOut:
            "\(providerName) didn't respond in time. Please try again."
        case .rateLimited:
            "\(providerName) is receiving too many requests. Wait a moment, then try again."
        case .offline:
            "Check your connection, then try again."
        case .authentication:
            "The sign-in information wasn't accepted. Check it and try again."
        case .serviceUnavailable:
            "\(providerName) can't be reached right now. Try again in a moment."
        case .invalidResponse:
            "The sign-in information couldn't be read. Check it and try again."
        case .unavailable:
            "\(providerName) sign-in isn't available in this build."
        case .unknown:
            "Something interrupted sign-in. Please try again."
        }
    }
}

extension UsageSnapshot {
    /// Windows bucketed so that consecutive windows resetting at the same
    /// moment (within a minute) share one reset footer — e.g. Claude's
    /// Weekly and per-model windows both reset with the weekly cycle.
    var windowGroups: [[LimitWindow]] {
        var groups: [[LimitWindow]] = []
        for window in windows {
            if let last = groups.last?.last,
               let a = last.resetsAt, let b = window.resetsAt,
               abs(a.timeIntervalSince(b)) < 60 {
                groups[groups.count - 1].append(window)
            } else {
                groups.append([window])
            }
        }
        return groups
    }

}
