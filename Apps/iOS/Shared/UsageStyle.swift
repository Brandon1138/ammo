import SwiftUI
import UsageKit

extension LimitWindow {
    /// Color semantics per SPEC: blue normally, amber at ≥75% used, red at ≥90%.
    var barColor: Color {
        if usedPercent >= 90 { .red } else if usedPercent >= 75 { .orange } else { .blue }
    }

    /// True once the window is worth calling out (amber/red territory).
    var isRunningLow: Bool { usedPercent >= 75 }

    var remainingPercentText: String { "\(Int(remainingPercent.rounded()))%" }
}
