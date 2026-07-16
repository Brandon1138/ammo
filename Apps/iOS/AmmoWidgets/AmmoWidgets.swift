import SwiftUI
import WidgetKit

@main
struct AmmoWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AmmoAccountWidget()
        AmmoAllAccountsWidget()
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

/// Medium widget: every configured account, one compact row each.
struct AmmoAllAccountsWidget: Widget {
    let kind = "AmmoAllAccounts"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AllAccountsProvider()) { entry in
            AllAccountsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("All Accounts")
        .description("Usage left across every account.")
        .supportedFamilies([.systemMedium])
    }
}
