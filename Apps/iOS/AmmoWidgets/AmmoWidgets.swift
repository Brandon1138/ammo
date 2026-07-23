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

/// Small home-screen widget (one account, bar per window) and the lock-screen
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
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

/// Ordered configured accounts. Small: percent list. Medium: bar per account.
/// Large: full details for the first two accounts.
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
        .description("Usage left across selected accounts in your preferred order.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
