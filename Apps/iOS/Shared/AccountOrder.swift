import Foundation

/// The order a person put their accounts in, expressed as account IDs.
///
/// Ordering is keyed to `StoredAccount.id` and nothing else, so it survives app
/// restarts, credential refreshes, and relabelling. An account the person has
/// never placed simply has no position here; it is never invented, because a
/// synthesized position would be indistinguishable from a deliberate one the
/// next time the list is arranged.
struct AccountOrder: Equatable, Sendable {
    /// Placed accounts, first to last. Duplicates are collapsed to their first
    /// occurrence so a position is always unambiguous.
    private(set) var ids: [UUID]
    private var positions: [UUID: Int]

    static let empty = AccountOrder(ids: [])

    init(ids: [UUID]) {
        var deduplicated: [UUID] = []
        var positions: [UUID: Int] = [:]
        deduplicated.reserveCapacity(ids.count)
        for id in ids where positions[id] == nil {
            positions[id] = deduplicated.count
            deduplicated.append(id)
        }
        self.ids = deduplicated
        self.positions = positions
    }

    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: UUID) -> Bool { positions[id] != nil }

    /// The person's rank for `id`, or nil when they have never placed it.
    func position(of id: UUID) -> Int? { positions[id] }

    /// Places `ids` that have no position yet at the end, keeping every
    /// existing position exactly where it was. This is what a newly added
    /// account gets: the end of the list, not a reshuffle of the list.
    func appending(_ ids: [UUID]) -> AccountOrder {
        let unplaced = ids.filter { positions[$0] == nil }
        guard !unplaced.isEmpty else { return self }
        return AccountOrder(ids: self.ids + unplaced)
    }

    /// Drops one account's position, closing the gap it leaves. Used when an
    /// account is removed so the stored order cannot grow without bound.
    func removing(_ id: UUID) -> AccountOrder {
        guard positions[id] != nil else { return self }
        return AccountOrder(ids: ids.filter { $0 != id })
    }

    /// Arranges `elements` by the person's order.
    ///
    /// Placed accounts come first, in their stored positions. Everything else
    /// follows in the order it was handed over — for the app's list that is
    /// insertion order, which keeps a freshly added account at the end instead
    /// of letting it jump around as its first snapshot lands.
    func arranged<Element>(
        _ elements: [Element],
        id: (Element) -> UUID
    ) -> [Element] {
        arranged(elements, id: id, tiebreak: nil)
    }

    /// Arranges `elements` by the person's order, resolving accounts they have
    /// never placed with `tiebreak`.
    ///
    /// The two groups are partitioned rather than sorted with one combined
    /// comparator: `tiebreak` only ever sees two unplaced accounts, so it never
    /// has to agree with the explicit positions to produce a stable result.
    func arranged<Element>(
        _ elements: [Element],
        id: (Element) -> UUID,
        tiebreak: ((Element, Element) -> Bool)?
    ) -> [Element] {
        var placed: [(position: Int, element: Element)] = []
        var unplaced: [Element] = []
        for element in elements {
            if let position = positions[id(element)] {
                placed.append((position, element))
            } else {
                unplaced.append(element)
            }
        }
        let ordered = placed.sorted { $0.position < $1.position }.map(\.element)
        guard let tiebreak else { return ordered + unplaced }
        return ordered + unplaced.sorted(by: tiebreak)
    }
}
