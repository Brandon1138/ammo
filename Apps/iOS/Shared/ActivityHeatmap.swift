import SwiftUI
import UsageKit
import WidgetKit

/// Week columns by weekday rows, ordered oldest to newest from left to right.
struct ActivityHeatmap: View {
    @Environment(\.widgetRenderingMode) private var renderingMode

    let days: [UsageActivityDay]
    var spacing: CGFloat = 3
    var cornerRadius: CGFloat = 2.5
    var matchesContainerCorners = false

    var body: some View {
        heatmap
            .aspectRatio(CGFloat(weekCount) / 7, contentMode: .fit)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var heatmap: some View {
        if matchesContainerCorners {
            canvas
                // WidgetKit supplies the parent container shape. Clipping the
                // complete grid with its relative shape makes only the cells
                // at the widget's outer corners inherit the concentric curve.
                .clipShape(ContainerRelativeShape())
        } else {
            canvas
        }
    }

    private var canvas: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let horizontalGaps = CGFloat(max(0, weekCount - 1)) * spacing
                let verticalGaps = CGFloat(6) * spacing
                let cellSize = floor(min(
                    (size.width - horizontalGaps) / CGFloat(weekCount),
                    (size.height - verticalGaps) / 7
                ))
                guard cellSize > 0 else { return }

                let contentWidth = cellSize * CGFloat(weekCount) + horizontalGaps
                let contentHeight = cellSize * 7 + verticalGaps
                let origin = CGPoint(
                    x: max(0, size.width - contentWidth),
                    y: max(0, (size.height - contentHeight) / 2)
                )

                for (index, day) in days.enumerated() where !day.isFuture {
                    let week = index / 7
                    let weekday = index % 7
                    let rect = CGRect(
                        x: origin.x + CGFloat(week) * (cellSize + spacing),
                        y: origin.y + CGFloat(weekday) * (cellSize + spacing),
                        width: cellSize,
                        height: cellSize
                    )
                    let shape = Path(roundedRect: rect,
                                     cornerRadius: min(cornerRadius, cellSize / 3))
                    context.fill(shape, with: .color(color(for: day)))
                }
            }
        }
    }

    private var weekCount: Int {
        max(1, Int(ceil(Double(days.count) / 7)))
    }

    private func color(for day: UsageActivityDay) -> Color {
        guard day.intensityLevel > 0 else { return .primary.opacity(0.09) }
        let opacities: [Double] = [0, 0.28, 0.48, 0.72, 1]
        let base: Color = renderingMode == .fullColor ? .blue : .primary
        return base.opacity(opacities[day.intensityLevel])
    }

    private var accessibilitySummary: Text {
        let activeDays = days.filter(\.isActive).count
        let observed = days.reduce(0) { $0 + $1.observedUsedPercent }
        return Text("Usage activity. \(activeDays) active days. \(Int(observed.rounded())) percent observed use.")
    }
}
