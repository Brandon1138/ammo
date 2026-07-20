import SwiftUI
import UsageKit
import WidgetKit

/// Official provider artwork. Claude, Codex, and Cursor deliberately have no
/// drawn fallback: if a first-party asset is missing, that is a build defect.
struct ProviderLogo: View {
    enum Role {
        case standard
        case menu
    }

    @Environment(\.widgetRenderingMode) private var renderingMode
    let provider: ProviderID
    var size: CGFloat = 20
    var role: Role = .standard

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .renderingMode(imageRenderingMode)
                    .widgetAccentedRenderingMode(provider == .cursor ? .fullColor : .accented)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            } else if let fallbackSymbolName = provider.fallbackSymbolName {
                Image(systemName: fallbackSymbolName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size * artworkScale, height: size * artworkScale)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var artworkScale: CGFloat {
        if role == .menu, provider == .codex || provider == .cursor {
            return 0.82
        }
        if provider == .codex || provider == .cursor,
           renderingMode != .fullColor {
            return 0.875
        }
        return 1
    }

    private var imageRenderingMode: Image.TemplateRenderingMode {
        if provider == .cursor || renderingMode == .fullColor {
            return .original
        }
        return .template
    }

    private var assetName: String? {
        if provider == .codex, renderingMode != .fullColor {
            return "logo-openai-monochrome"
        }
        if provider == .cursor, renderingMode != .fullColor {
            return "logo-cursor-monochrome"
        }
        return provider.logoAssetName
    }
}

private extension ProviderID {
    var logoAssetName: String? {
        switch self {
        case .claude: "logo-claude"
        case .codex: "logo-codex"
        case .cursor: "logo-cursor"
        case .antigravity: nil
        }
    }

    var fallbackSymbolName: String? {
        switch self {
        case .antigravity: "circle.dotted.and.circle"
        case .claude, .codex, .cursor: nil
        }
    }
}

#Preview("Logos", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        ForEach(ProviderID.allCases) { ProviderLogo(provider: $0, size: 32) }
    }
    .padding()
}
