import Foundation

enum AccountRetryState: Equatable {
    case ready
    case coolingDown(until: Date)
    case refreshing

    init(outcome: RefreshOutcome) {
        switch outcome {
        case .refreshed:
            self = .ready
        case .cached(_, let nextEligibleAt):
            self = .coolingDown(until: nextEligibleAt)
        case .failed(_, _, let nextEligibleAt, _):
            self = nextEligibleAt.map(Self.coolingDown) ?? .ready
        }
    }

    var isCoolingDown: Bool {
        if case .coolingDown = self { return true }
        return false
    }

    func resolved(at date: Date) -> Self {
        if case .coolingDown(let eligibleAt) = self, eligibleAt <= date {
            return .ready
        }
        return self
    }
}

enum RefreshFailureBackoff {
    static func delay(consecutiveFailures: Int, status: Int?) -> TimeInterval {
        let exponent = min(max(consecutiveFailures - 1, 0), 6)
        let base: TimeInterval = status == 429 ? 5 * 60 : 60
        let ceiling: TimeInterval = status == 429 ? 60 * 60 : 15 * 60
        return min(ceiling, base * pow(2, Double(exponent)))
    }
}
