import Foundation
import Testing
import UsageKit

@testable import Ammo

/// MIK-157: the account order belongs to the person, not to the cache.
///
/// Before this, order was whatever `SharedStore` happened to hold plus a
/// "most complete usage data" heuristic, so removing and re-adding an account
/// silently demoted it and nothing could be done about it. The explicit order
/// is now the primary key everywhere accounts are ranked; the heuristic is
/// only consulted between accounts that have never been placed.
@MainActor
@Suite("MIK-157 user-controlled account order")
struct MIK157Tests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private let codexID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let claudeID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let cursorID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let secondCodexID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    // MARK: - Persistence

    @Test("An order round-trips through the shared store")
    func orderRoundTripsOnDisk() throws {
        try withTemporaryStore { fileURL, lock in
            // Nothing written yet reads as "never ordered", which is what keeps
            // the pre-MIK-157 heuristic ordering in place for existing installs.
            #expect(AccountOrderStore.load(fileURL: fileURL, lock: lock) == .empty)

            let order = AccountOrder(ids: [cursorID, codexID, claudeID])
            try AccountOrderStore.save(order, fileURL: fileURL, lock: lock)

            let reloaded = AccountOrderStore.load(fileURL: fileURL, lock: lock)
            #expect(reloaded == order)
            #expect(reloaded.ids == [cursorID, codexID, claudeID])
            #expect(reloaded.position(of: cursorID) == 0)
            #expect(reloaded.position(of: claudeID) == 2)
            #expect(reloaded.position(of: secondCodexID) == nil)
        }
    }

    @Test("A rewritten order replaces the previous one rather than merging")
    func savingReplacesThePreviousOrder() throws {
        try withTemporaryStore { fileURL, lock in
            try AccountOrderStore.save(AccountOrder(ids: [codexID, claudeID]),
                                       fileURL: fileURL, lock: lock)
            try AccountOrderStore.save(AccountOrder(ids: [claudeID, codexID]),
                                       fileURL: fileURL, lock: lock)

            #expect(AccountOrderStore.load(fileURL: fileURL, lock: lock).ids
                == [claudeID, codexID])
        }
    }

    @Test("A repeated ID keeps only its first position")
    func repeatedIDsCollapse() {
        let order = AccountOrder(ids: [codexID, claudeID, codexID])

        #expect(order.ids == [codexID, claudeID])
        #expect(order.position(of: codexID) == 0)
    }

    // MARK: - Ordering

    @Test("An explicitly placed account outranks better usage data")
    func explicitOrderIsThePrimaryKey() {
        // Claude has the richest snapshot and would win on the heuristic alone;
        // Codex has none at all and is the account the person placed first.
        let codex = state(id: codexID, provider: .codex, label: "Codex", snapshot: nil)
        let claude = fullState(id: claudeID, provider: .claude, label: "Claude")

        let heuristic = WidgetAccountOrder.defaultOrder([codex, claude], order: .empty)
        #expect(heuristic.map(\.id) == [claudeID, codexID])

        let chosen = WidgetAccountOrder.defaultOrder(
            [claude, codex], order: AccountOrder(ids: [codexID, claudeID]))
        #expect(chosen.map(\.id) == [codexID, claudeID])
    }

    @Test("Accounts without a position keep the old heuristic, behind the placed ones")
    func unplacedAccountsFallBackToTheHeuristic() {
        // Cursor is placed. Codex has windows, Claude has none — the heuristic
        // ranks Codex above Claude, and both stay behind the placed Cursor.
        let cursor = state(id: cursorID, provider: .cursor, label: "Cursor", snapshot: nil)
        let codex = fullState(id: codexID, provider: .codex, label: "Codex")
        let claude = state(id: claudeID, provider: .claude, label: "Claude", snapshot: nil)

        let ordered = WidgetAccountOrder.defaultOrder(
            [claude, codex, cursor], order: AccountOrder(ids: [cursorID]))

        #expect(ordered.map(\.id) == [cursorID, codexID, claudeID])
    }

    @Test("A new account appends instead of reshuffling the placed ones")
    func newAccountsAppendAtTheEnd() {
        let order = AccountOrder(ids: [cursorID, codexID])
        let grown = order.appending([codexID, cursorID, claudeID])

        #expect(grown.ids == [cursorID, codexID, claudeID])
        #expect(grown.position(of: cursorID) == 0)
        #expect(grown.position(of: codexID) == 1)
        #expect(grown.position(of: claudeID) == 2)

        // The freshly added Claude has the best data of the three and would be
        // ranked first by the heuristic. It still lands last.
        let claude = fullState(id: claudeID, provider: .claude, label: "Claude")
        let cursor = state(id: cursorID, provider: .cursor, label: "Cursor", snapshot: nil)
        let codex = state(id: codexID, provider: .codex, label: "Codex", snapshot: nil)
        let ordered = WidgetAccountOrder.defaultOrder([claude, cursor, codex], order: order)

        #expect(ordered.map(\.id) == [cursorID, codexID, claudeID])
    }

    @Test("Removing an account closes its gap and leaves the rest in place")
    func removingAnAccountClosesTheGap() {
        let order = AccountOrder(ids: [cursorID, codexID, claudeID]).removing(codexID)

        #expect(order.ids == [cursorID, claudeID])
        #expect(order.position(of: claudeID) == 1)
        #expect(!order.contains(codexID))
    }

    @Test("The order is keyed to the account ID, not to its label or snapshot")
    func orderSurvivesRelabellingAndRefresh() throws {
        try withTemporaryStore { fileURL, lock in
            try AccountOrderStore.save(AccountOrder(ids: [claudeID, codexID]),
                                       fileURL: fileURL, lock: lock)
            let order = AccountOrderStore.load(fileURL: fileURL, lock: lock)

            // Same IDs, everything else different: renamed, and one of them has
            // been refreshed into a snapshot it did not have before.
            let codex = fullState(id: codexID, provider: .codex, label: "Work Codex")
            let claude = state(id: claudeID, provider: .claude, label: "zzz", snapshot: nil)

            #expect(WidgetAccountOrder.defaultOrder([codex, claude], order: order).map(\.id)
                == [claudeID, codexID])
        }
    }

    // MARK: - Provider slots

    @Test("A provider panel takes the person's top-ranked account of that provider")
    func providerSlotHonorsTheExplicitOrder() {
        // Both are Codex. The placed one reports nothing yet; the other has a
        // full window and wins on the heuristic.
        let placed = state(id: secondCodexID, provider: .codex, label: "Personal", snapshot: nil)
        let complete = fullState(id: codexID, provider: .codex, label: "Work")

        let heuristic = WidgetProviderPanels.slots(
            states: [placed, complete], showingCodexSpark: false, order: .empty)
        #expect(heuristic.first(where: { $0.provider == .codex })?.state?.id == codexID)

        let chosen = WidgetProviderPanels.slots(
            states: [placed, complete],
            showingCodexSpark: false,
            order: AccountOrder(ids: [secondCodexID, codexID]))
        #expect(chosen.first(where: { $0.provider == .codex })?.state?.id == secondCodexID)
    }

    @Test("A provider whose accounts are all unplaced keeps the heuristic slot")
    func providerSlotFallsBackWhenNoneArePlaced() {
        let placedClaude = fullState(id: claudeID, provider: .claude, label: "Claude")
        let bareCodex = state(id: secondCodexID, provider: .codex, label: "Personal", snapshot: nil)
        let completeCodex = fullState(id: codexID, provider: .codex, label: "Work")

        // Only the Claude account is placed, so the Codex panel is still decided
        // by usage completeness.
        let slots = WidgetProviderPanels.slots(
            states: [bareCodex, completeCodex, placedClaude],
            showingCodexSpark: false,
            order: AccountOrder(ids: [claudeID]))

        #expect(slots.first(where: { $0.provider == .codex })?.state?.id == codexID)
        #expect(slots.first(where: { $0.provider == .claude })?.state?.id == claudeID)
    }

    // MARK: - Helpers

    private func withTemporaryStore(
        _ body: (URL, SharedFileLock) throws -> Void
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ammo-account-order-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("account-order.json"),
                 SharedFileLock(url: directory.appendingPathComponent("account-order.lock")))
    }

    private func state(id: UUID,
                       provider: ProviderID,
                       label: String,
                       snapshot: UsageSnapshot?) -> AccountState {
        AccountState(account: StoredAccount(id: id, provider: provider, label: label),
                     snapshot: snapshot,
                     lastError: nil,
                     updatedAt: snapshot?.fetchedAt)
    }

    private func fullState(id: UUID, provider: ProviderID, label: String) -> AccountState {
        state(id: id,
              provider: provider,
              label: label,
              snapshot: UsageSnapshot(
                provider: provider,
                plan: nil,
                windows: [
                    LimitWindow(kind: .weekly,
                                label: "Weekly",
                                usedPercent: 40,
                                resetsAt: now.addingTimeInterval(86_400)),
                ],
                fetchedAt: now))
    }
}
