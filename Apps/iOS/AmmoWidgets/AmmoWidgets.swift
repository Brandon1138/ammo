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
/// meter plus ledger of reset/credit facts) and lock-screen
/// circular gauge. Account is chosen per-widget via AppIntentConfiguration.
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
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

/// Ordered configured accounts. Small: percent list. Medium: bar per account.
/// Large: full details for the first two accounts. Extra large (iPad): a 2×2
/// panel per shipping provider, including providers without an account.
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
                + "selected order; extra large shows a fixed panel per provider.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
    }
}
