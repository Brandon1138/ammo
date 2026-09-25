/// Keeps a pinned widget on its account when its selected window disappears.
public enum PinnedLimitSelection {
    public static func resolve(windowID: String, in windows: [LimitWindow]) -> LimitWindow? {
        windows.first(where: { $0.id == windowID })
            ?? preferredWindow(in: windows)
    }

    public static func preferredWindow(in windows: [LimitWindow]) -> LimitWindow? {
        windows.first(where: { $0.kind == .weekly })
            ?? windows.first(where: { $0.kind == .monthly })
            ?? windows.first
    }
}
