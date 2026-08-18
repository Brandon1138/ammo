import SwiftUI
import WidgetKit

/// Open circular gauge chrome shared by Lock Screen usage meters.
///
/// The arc leaves a 90-degree gap at six o'clock for the gauge label. Fill
/// meters deplete the arc with their value; marker meters keep a full track and
/// move a dot to the value, matching single-window provider semantics.
struct AmmoAccessoryCircularGaugeStyle: GaugeStyle {
    enum Variant {
        case fill
        case marker
    }

    let variant: Variant

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let center = CGPoint(
                x: geometry.size.width / 2,
                y: geometry.size.height / 2
            )
            let lineWidth = max(4, min(5, side * 0.085))
            let radius = (side - lineWidth) / 2
            let progress = min(max(configuration.value, 0), 1)

            ZStack {
                gaugeArc
                    .stroke(
                        .tertiary,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round
                        )
                    )
                    .frame(width: side - lineWidth, height: side - lineWidth)
                    .position(center)

                switch variant {
                case .fill:
                    Circle()
                        .trim(from: 0, to: 0.75 * progress)
                        .rotation(.degrees(135))
                        .stroke(
                            .primary,
                            style: StrokeStyle(
                                lineWidth: lineWidth,
                                lineCap: .round
                            )
                        )
                        .frame(width: side - lineWidth, height: side - lineWidth)
                        .position(center)
                        .widgetAccentable()
                case .marker:
                    Circle()
                        .fill(.primary)
                        .frame(width: lineWidth + 2, height: lineWidth + 2)
                        .position(markerPosition(
                            center: center,
                            radius: radius,
                            progress: progress
                        ))
                        .widgetAccentable()
                }

                configuration.currentValueLabel
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: side * 0.62)
                    .position(x: center.x, y: center.y - 2)

                configuration.label
                    .frame(
                        width: geometry.size.width,
                        height: geometry.size.height,
                        alignment: .bottom
                    )
            }
        }
    }

    /// Circle trim starts at three o'clock. Rotating 135 degrees puts arc ends
    /// around the bottom gap and makes progress run clockwise.
    private var gaugeArc: some Shape {
        Circle()
            .trim(from: 0, to: 0.75)
            .rotation(.degrees(135))
    }

    private func markerPosition(
        center: CGPoint,
        radius: CGFloat,
        progress: Double
    ) -> CGPoint {
        let angle = Angle.degrees(135 + (270 * progress)).radians
        return CGPoint(
            x: center.x + radius * CGFloat(cos(angle)),
            y: center.y + radius * CGFloat(sin(angle))
        )
    }
}
