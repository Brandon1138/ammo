import SwiftUI
import UsageKit
import WidgetKit

struct AccountWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if let state = entry.state {
            switch family {
            case .accessoryCircular:
                CircularGaugeView(state: state)
            default:
                SmallAccountView(state: state)
            }
        } else {
            SetupHintView()
        }
    }
}

struct SetupHintView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "battery.0percent")
            Text("Set up in Ammo")
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
    }
}

/// systemSmall: provider glyph + label, a "% left" bar per window, and the
/// soonest reset as a live relative countdown.
struct SmallAccountView: View {
    let state: AccountState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: state.account.provider.symbolName)
                    .font(.caption.weight(.semibold))
                Text(state.account.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            if let snapshot = state.snapshot {
                ForEach(snapshot.windows.prefix(3)) { window in
                    WindowBar(window: window)
                }
                Spacer(minLength: 0)
                if let resetsAt = soonestReset(snapshot), resetsAt > Date() {
                    Text("resets \(Text(resetsAt, style: .relative))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Spacer(minLength: 0)
                Text(state.lastError == nil ? "No data yet" : "Fetch failed — open Ammo")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }

    private func soonestReset(_ snapshot: UsageSnapshot) -> Date? {
        snapshot.windows.compactMap(\.resetsAt).filter { $0 > Date() }.min()
    }
}

struct WindowBar: View {
    let window: LimitWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(window.label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(window.barColor)
            }
            ProgressView(value: window.remainingPercent, total: 100)
                .progressViewStyle(.linear)
                .tint(window.barColor)
                .scaleEffect(y: 0.8)
        }
    }
}

/// accessoryCircular: gauge of "% left" for the account's most-consumed window.
struct CircularGaugeView: View {
    let state: AccountState

    var body: some View {
        if let worst = state.snapshot?.worstWindow {
            Gauge(value: worst.remainingPercent, in: 0...100) {
                Image(systemName: state.account.provider.symbolName)
            } currentValueLabel: {
                Text("\(Int(worst.remainingPercent.rounded()))%")
            }
            .gaugeStyle(.accessoryCircular)
            .tint(worst.barColor)
        } else {
            Gauge(value: 0, in: 0...100) {
                Image(systemName: state.account.provider.symbolName)
            } currentValueLabel: {
                Text("—")
            }
            .gaugeStyle(.accessoryCircular)
        }
    }
}

/// systemMedium: one compact row per account.
struct AllAccountsWidgetView: View {
    let entry: AllAccountsEntry

    var body: some View {
        if entry.states.isEmpty {
            SetupHintView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(entry.states.prefix(4)) { state in
                    AccountRow(state: state)
                }
            }
        }
    }
}

struct AccountRow: View {
    let state: AccountState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: state.account.provider.symbolName)
                .font(.caption.weight(.semibold))
                .frame(width: 16)
            Text(state.account.label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)
            if let worst = state.snapshot?.worstWindow {
                ProgressView(value: worst.remainingPercent, total: 100)
                    .progressViewStyle(.linear)
                    .tint(worst.barColor)
                Text("\(Int(worst.remainingPercent.rounded()))%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(worst.barColor)
                    .frame(width: 40, alignment: .trailing)
            } else {
                Text(state.lastError == nil ? "no data" : "error")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
}
