import SwiftUI
import UsageKit

extension LimitWindow {
    /// Color semantics per SPEC: tint normally, amber at ≥75% used, red at ≥90%.
    var barColor: Color {
        if usedPercent >= 90 { .red } else if usedPercent >= 75 { .orange } else { .accentColor }
    }
}

extension ProviderID {
    var symbolName: String {
        switch self {
        case .claude: "asterisk"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow"
        case .antigravity: "circle.dotted.and.circle"
        }
    }
}
