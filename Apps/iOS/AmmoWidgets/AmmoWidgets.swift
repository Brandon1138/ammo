import SwiftUI
import WidgetKit

@main
struct AmmoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AmmoAccountWidget()
        AmmoAllAccountsWidget()
        AmmoActivityWidget()
    }
}

/// Contribution-style daily activity for one account and allowance.
struct AmmoActivityWidget: Widget {
    let kind = "AmmoActivity"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectLimitIntent.self,
                               provider: ActivityTimelineProvider()) { entry in
            ActivityWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Activity")
        .description("Daily usage activity for one account and limit.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Home-screen widget for one account (small: bar per window; medium: headline
/// meter plus ledger of reset/credit facts). Account is chosen per-widget via
/// AppIntentConfiguration. The Lock Screen circular gauge is deferred to a
/// post-launch build; its pre-removal state lives on the
/// `deferred/lockscreen-widgets` branch.
struct AmmoAccountWidget: Widget {
    let kind = "AmmoAccount"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectAccountIntent.self,
                               provider: AccountTimelineProvider()) { entry in
            AccountWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Account")
        .description("Usage left for one account.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

/// Ordered configured accounts. Small: percent list. Medium: bar per account.
/// Large: full details for the first two accounts. Extra large portrait
/// (iPhone, iOS 27+): four divider-separated provider sections using the same
/// detail language as Large, including providers without an account.
struct AmmoAllAccountsWidget: Widget {
    let kind = "AmmoAllAccounts"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind,
                               intent: SelectAccountsIntent.self,
                               provider: AllAccountsProvider()) { entry in
            AllAccountsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Accounts")
        .description(
            "Usage left across your accounts. Small, medium, and large follow your "
                + "selected order; the tall size shows a fixed section per provider.")
        .supportedFamilies(WidgetProviderPanels.accountsFamilies)
    }
}
