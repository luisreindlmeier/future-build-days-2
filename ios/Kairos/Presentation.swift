import Foundation

enum Mood: String, CaseIterable, Sendable {
    case idle, curious, smile, happy, wink, cheer
}

struct Fact: Identifiable, Sendable {
    let label: String
    let value: String

    var id: String { label }
}

struct Bar: Identifiable, Sendable {
    let label: String
    let value: Double
    let text: String
    var highlighted = false

    var id: String { label }
}

/// The three rings on Home. Each is one of the backend's bank-data scores and one part of the tree.
enum CategoryID: String, CaseIterable, Identifiable, Sendable {
    case spending, saving, investing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spending: "Spending"
        case .saving: "Saving"
        case .investing: "Investing"
        }
    }

    var question: String {
        switch self {
        case .spending: "The leaves of your tree: what you spend, against households like yours."
        case .saving: "The roots of your tree: what you have set aside, and for what."
        case .investing: "The trunk of your tree: what works for your future."
        }
    }

    var symbol: String {
        switch self {
        case .spending: "credit-card"
        case .saving: "piggy-bank"
        case .investing: "trending-up"
        }
    }

    var illustration: String { "illustration-\(rawValue)" }
}

/// One row of a category page: a leaf cluster, a root or a property of the trunk.
struct Area: Identifiable, Sendable {
    let id: String
    let icon: String
    let title: String
    let health: Health
    let word: String
    let detail: String
    let facts: [Fact]
    var actionID: String?
}

extension Workspace {
    func score(_ category: CategoryID) -> Int {
        switch category {
        case .spending: assessment.spendScore
        case .saving: assessment.savingsScore
        case .investing: assessment.investScore
        }
    }

    var agentActions: [AgentAction] { prediction.actions?.output?.actions ?? [] }
    var forecast: PredictionOutput? { prediction.prediction?.output }
    var activeCommitments: [TrackedAction] { progress.actions.filter(\.isActive) }

    func tracked(_ action: AgentAction) -> TrackedAction? {
        guard let id = actionMappings[action.actionID]?.backendActionId else { return nil }
        return progress.actions.first { $0.actionId == id && $0.isActive }
    }

    func areas(_ category: CategoryID) -> [Area] {
        switch category {
        case .spending:
            return tree.leaves.map { leaf in
                var facts: [Fact] = []
                if let amount = leaf.monthlyAmount { facts.append(Fact(label: "You, a month", value: Format.euro(amount))) }
                if let peers = leaf.peerAverage { facts.append(Fact(label: "Households like yours", value: Format.euro(peers))) }
                if let budget = leaf.monthlyBudget { facts.append(Fact(label: "A healthy limit", value: Format.euro(budget))) }
                if let trend = leaf.trendPct, abs(trend) >= 1 { facts.append(Fact(label: "Trend", value: "\(trend > 0 ? "up" : "down") \(Format.number(abs(trend), decimals: 0))%")) }
                let action = "limit_" + leaf.category.lowercased()
                let word = switch leaf.health {
                case "HEALTHY": "In line"
                case "WILTING": "Above peers"
                case "ROTTEN": "Far above peers"
                default: "Not measured"
                }
                return Area(id: leaf.category, icon: Self.leafIcon(leaf.category), title: leaf.label, health: Health(status: leaf.health), word: word,
                            detail: leaf.detail, facts: facts, actionID: agentActions.contains { $0.actionID == action } ? action : nil)
            }
        case .saving:
            return tree.roots.map { root in
                var facts: [Fact] = []
                if let balance = root.balance { facts.append(Fact(label: "Set aside", value: Format.euro(balance))) }
                if let target = root.target, target > 0 { facts.append(Fact(label: "Target", value: Format.euro(target))) }
                let health = Health(status: root.status)
                return Area(id: root.category, icon: Self.rootIcon(root.category), title: root.label, health: health, word: health.title, detail: root.detail,
                            facts: facts, actionID: root.category == "EMERGENCY" && agentActions.contains { $0.actionID == "start_buffer" } ? "start_buffer" : nil)
            }
        case .investing:
            let trunk = tree.trunk
            var amount: [Fact] = []
            if let invested = trunk.invested { amount.append(Fact(label: "Invested", value: Format.euro(invested))) }
            if let idle = trunk.idleCash { amount.append(Fact(label: "Idle in cash", value: Format.euro(idle))) }
            if let share = assessment.investedShare { amount.append(Fact(label: "Share of your investable money", value: Format.percent(share))) }
            var spread: [Fact] = []
            if let diversification = assessment.diversification { spread.append(Fact(label: "Diversification", value: Format.percent(diversification))) }
            if let largest = assessment.largestPositionShare { spread.append(Fact(label: "Largest single position", value: Format.percent(largest))) }
            let rings = Health.missing.rawValue + (trunk.rings >= 3 ? 3 : trunk.rings >= 1 ? 2 : 1)
            let cracks: Health = trunk.cracks == 0 ? .strong : trunk.cracks == 1 ? .growing : .needsCare
            let invest = agentActions.contains { $0.actionID == "save_more_tomorrow" } ? "save_more_tomorrow" : nil
            let diversify = agentActions.contains { $0.actionID == "family_diversification_plan" } ? "family_diversification_plan" : nil
            return [
                Area(id: "amount", icon: "trending-up", title: "Money at work", health: Health(share: trunk.thickness), word: Health(share: trunk.thickness).title,
                     detail: trunk.detail, facts: amount, actionID: invest),
                Area(id: "stability", icon: "scale", title: "Stability", health: Health(share: trunk.stability), word: Health(share: trunk.stability).title,
                     detail: "How steady your portfolio stands when markets fall. Spread and single positions decide it.", facts: spread, actionID: diversify),
                Area(id: "rings", icon: "calendar-check", title: "Consistency", health: Health(rawValue: rings) ?? .needsCare, word: Format.count(trunk.rings, "year"),
                     detail: "Every year of regular investing adds a ring to the trunk. You have \(Format.count(trunk.rings, "ring")).", facts: [], actionID: invest),
                Area(id: "cracks", icon: "shield-check", title: "Risks to look at", health: cracks, word: trunk.cracks == 0 ? "Steady" : Format.count(trunk.cracks, "crack"),
                     detail: trunk.cracks == 0 ? "No cracks in the trunk." : "\(Format.count(trunk.cracks, "crack")) in the trunk: \(trunk.cracks == 1 ? "a risk" : "risks") to go through with your advisor.",
                     facts: [], actionID: agentActions.contains { $0.actionID == "write_crash_rules" } ? "write_crash_rules" : nil),
            ]
        }
    }

    func summary(_ category: CategoryID) -> String {
        let rows = areas(category).filter { $0.health != .missing }
        guard let best = rows.max(by: { $0.health < $1.health }), let worst = rows.min(by: { $0.health < $1.health }) else { return "Nothing to rate here yet." }
        if worst.health == .strong { return "All of it is in good shape." }
        return best.id == worst.id ? worst.detail : "\(best.title) is in the best shape. \(worst.title) needs the most care."
    }

    /// What the scan did, in the order it did it, with the figures of this customer.
    var scanSteps: [ScanStep] {
        let peers = tree.leaves.first?.peerGroup ?? "households with your income"
        return [
            ScanStep(id: 1, title: "Reading your accounts", detail: "\(tree.leaves.count) spending categories, \(tree.roots.count) savings pots and your portfolio"),
            ScanStep(id: 2, title: "Comparing your spending", detail: "Against \(peers)"),
            ScanStep(id: 3, title: "Measuring your well-being", detail: "The CFPB well-being model, age \(tree.wellbeing?.ageBand ?? "group")"),
            ScanStep(id: 4, title: "Simulating your futures", detail: "\((prediction.engine?.paths ?? 2000).formatted(.number.locale(Locale(identifier: "en_GB")))) futures over \(prediction.chart?.years ?? 15) years"),
            ScanStep(id: 5, title: "Growing your tree", detail: tree.headline),
        ]
    }

    static func leafIcon(_ category: String) -> String {
        switch category {
        case "HOUSING": "house"
        case "GROCERIES": "shopping-cart"
        case "TRANSPORT": "bus"
        case "EATING_OUT": "utensils"
        case "SHOPPING": "shopping-bag"
        case "TRAVEL": "plane"
        case "SUBSCRIPTIONS": "repeat"
        default: "receipt"
        }
    }

    static func rootIcon(_ category: String) -> String {
        switch category {
        case "EMERGENCY": "life-buoy"
        case "GOALS": "target"
        case "RETIREMENT": "sunset"
        case "PROTECTION": "umbrella"
        default: "piggy-bank"
        }
    }
}

struct ScanStep: Identifiable, Sendable {
    let id: Int
    let title: String
    let detail: String
}

extension AgentAction {
    var bucketTitle: String {
        switch bucket {
        case "this_week": "This week"
        case "this_month": "This month"
        case "with_your_advisor": "With your advisor"
        default: bucket.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var needsAdvisor: Bool { bucket == "with_your_advisor" }

    /// "goal +11 points" as "Goal +11 points".
    var effect: String? {
        guard let label = impact?.effectLabel, !label.isEmpty else { return nil }
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    var category: CategoryID {
        if actionID.hasPrefix("limit_") || actionID.contains("subscription") || actionID.contains("purchase") || actionID.contains("spending") { return .spending }
        if actionID.contains("buffer") || actionID.contains("will") || actionID.contains("protection") { return .saving }
        return .investing
    }
}
