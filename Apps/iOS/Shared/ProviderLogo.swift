import SwiftUI
import UsageKit
import WidgetKit

/// Official provider artwork. Shipping providers deliberately have no drawn
/// fallback: if a first-party asset is missing, that is a build defect.
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
        // Native menus extract the image from Label and ignore SwiftUI frame
        // modifiers, so these variants carry their optical inset in the asset.
        if role == .menu {
            switch provider {
            case .codex: return "logo-codex-menu"
            case .cursor: return "logo-cursor-menu"
            case .claude, .openRouter, .antigravity: break
            }
        }
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
        case .openRouter: "logo-openrouter"
        case .antigravity: nil
        }
    }

    var fallbackSymbolName: String? {
        switch self {
        case .antigravity: "circle.dotted.and.circle"
        case .claude, .codex, .cursor, .openRouter: nil
        }
    }
}

#Preview("Logos", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        ForEach(ProviderID.allCases) { ProviderLogo(provider: $0, size: 32) }
    }
    .padding()
}
