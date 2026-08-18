import OSLog

enum AmmoLog {
    static let sharedStore = Logger(subsystem: "com.brandon.ammo", category: "shared-store")
    static let refresh = Logger(subsystem: "com.brandon.ammo", category: "refresh")
    static let widgetInvalidation = Logger(subsystem: "com.brandon.ammo", category: "widget-invalidation")
    static let widgetTimeline = Logger(subsystem: "com.brandon.ammo.widgets", category: "timeline")
    static let widgetRender = Logger(subsystem: "com.brandon.ammo.widgets", category: "render")
}
