import Foundation

/// The backend's responses, as it sends them. Field names follow the team's API (`backend/README.md`).

struct UserSummary: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    var age: Int?
    var situation: String?
    var overallHealth: Int?
    var status: String?
    var headline: String?
}

struct Workspace: Decodable, Sendable {
    let userId: String
    let tree: TreeState
    let assessment: Assessment
    let progress: Progress
    let prediction: PredictionEnvelope
    var actionMappings: [String: ActionMapping] = [:]
    var projects: [Project] = []

    private enum CodingKeys: String, CodingKey { case userId, tree, assessment, progress, prediction, actionMappings, projects }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        tree = try c.decode(TreeState.self, forKey: .tree)
        assessment = try c.decode(Assessment.self, forKey: .assessment)
        progress = try c.decode(Progress.self, forKey: .progress)
        prediction = try c.decode(PredictionEnvelope.self, forKey: .prediction)
        actionMappings = (try? c.decode([String: ActionMapping].self, forKey: .actionMappings)) ?? [:]
        projects = (try? c.decode([Project].self, forKey: .projects)) ?? []
    }
}

// MARK: Tree

struct TreeState: Decodable, Equatable, Sendable {
    let name: String
    let stage: String
    let overallHealth: Int
    let status: String
    let headline: String
    let roots: [Root]
    let trunk: Trunk
    let leaves: [Leaf]
    let branches: [Branch]
    let soil: Soil
    let weather: Weather
    var wellbeing: Wellbeing?
}

struct Root: Decodable, Equatable, Identifiable, Sendable {
    let category: String
    let label: String
    let depth: Double
    let thickness: Double
    let status: String
    var balance: Double?
    var target: Double?
    let detail: String

    var id: String { category }
}

struct Trunk: Decodable, Equatable, Sendable {
    let thickness: Double
    let height: Double
    let rings: Int
    let cracks: Int
    let stability: Double
    let barkHealth: Double
    let status: String
    var invested: Double?
    var idleCash: Double?
    let detail: String
}

struct Leaf: Decodable, Equatable, Identifiable, Sendable {
    let category: String
    let label: String
    var essential: Bool?
    let size: Double
    let health: String
    var monthlyAmount: Double?
    var monthlyBudget: Double?
    var peerAverage: Double?
    var peerGroup: String?
    var trendPct: Double?
    let detail: String

    var id: String { category }
}

struct Branch: Decodable, Equatable, Identifiable, Sendable {
    let projectId: String
    let name: String
    let type: String
    let length: Double
    var angleDeg: Double?
    var fruit: Bool?
    var blossom: Bool?
    let detail: String

    var id: String { projectId }
}

struct Soil: Decodable, Equatable, Sendable {
    let richness: Double
    let layers: Int
    var trainingsCompleted: Int?
    let status: String
    let detail: String
}

struct Weather: Decodable, Equatable, Sendable {
    let type: String
    let reason: String
}

struct Wellbeing: Decodable, Equatable, Sendable {
    var ageBand: String?
    var predictedScore: Double?
    var percentile: Double?
    var dimensions: [String: Double]?
}

// MARK: Assessment

struct Assessment: Decodable, Sendable {
    let overallScore: Int
    let savingsScore: Int
    let investScore: Int
    let spendScore: Int
    let knowledgeScore: Int
    var monthlySpend: Double?
    var savingsRate: Double?
    var bufferMonths: Double?
    var investedShare: Double?
    var diversification: Double?
    var largestPositionShare: Double?
    var idleCash: Double?
    var habits: [Habit] = []
    var context: CustomerContext?
    var findings: [String] = []
}

struct Habit: Decodable, Identifiable, Sendable {
    let category: String
    var monthlyAverage: Double?
    var monthlyBudget: Double?
    var peerAverage: Double?
    var peerGroup: String?
    var trendPct: Double?
    let health: String
    var reason: String?

    var id: String { category }
}

struct CustomerContext: Decodable, Sendable {
    var lifeStage: String?
    var risk: String?
    var flags: [String]?
    var goals: [String]?
}

// MARK: Progress

struct Progress: Decodable, Sendable {
    let month: String
    var monthsTracked: Int?
    var healthChangeLastMonth: Int?
    var healthChangeSinceStart: Int?
    var trend: String?
    var latestEvents: [String] = []
    var actions: [TrackedAction] = []
}

struct TrackedAction: Decodable, Identifiable, Sendable {
    let actionId: String
    let title: String
    let status: String
    var committedIn: String?
    var verifiedIn: String?
    var evidence: String?

    var id: String { actionId }
    var isActive: Bool { status == "COMMITTED" || status == "VERIFIED" }
}

struct Project: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let type: String
    let targetAmount: Double
    let savedAmount: Double
    var targetDate: String?
}

// MARK: Prediction and actions (the Python agents write snake_case)

struct PredictionEnvelope: Decodable, Sendable {
    let status: String
    var chart: ForecastChart?
    var prediction: PredictionResult?
    var actions: ActionsResult?
    var engine: Engine?
    var error: String?
}

struct PredictionResult: Decodable, Sendable {
    var source: String?
    var output: PredictionOutput?
}

struct ActionsResult: Decodable, Sendable {
    var source: String?
    var output: ActionsOutput?
}

struct Engine: Decodable, Sendable {
    struct Scenario: Decodable, Identifiable, Sendable {
        let id: String
        let label: String
    }

    var scenarios: [Scenario] = []
    var paths: Int?
}

struct ForecastChart: Decodable, Sendable {
    struct Band: Decodable, Sendable {
        let p10: [Double]
        let p50: [Double]
        let p90: [Double]
        var riskBelowToday: Double?
    }

    let startAge: Int
    let years: Int
    let wealthNow: Double
    let todayPath: Band
    let fullPlan: Band
    var byScenario: [String: Band] = [:]
}

struct PredictionOutput: Decodable, Sendable {
    struct BestChange: Decodable, Sendable {
        var scenarioID: String?
        var why: String?
        var firstStep: String?

        private enum CodingKeys: String, CodingKey { case scenarioID = "scenario_id", why, firstStep = "first_step" }
    }

    struct WatchOut: Decodable, Sendable {
        var sentence: String?
    }

    struct FutureSelves: Decodable, Sendable {
        var sameHabits: String?
        var withChanges: String?

        private enum CodingKeys: String, CodingKey { case sameHabits = "same_habits", withChanges = "with_changes" }
    }

    struct Comparison: Decodable, Identifiable, Sendable {
        let scenarioID: String
        let whatHappens: String

        var id: String { scenarioID }
        private enum CodingKeys: String, CodingKey { case scenarioID = "scenario_id", whatHappens = "what_happens" }
    }

    var headline: String?
    var ifNothingChanges: String?
    var futureSelves: FutureSelves?
    var whatItMeans: [String]?
    var bestChange: BestChange?
    var watchOut: WatchOut?
    var tradeOff: String?
    var comparison: [Comparison]?
    var disclaimer: String?

    private enum CodingKeys: String, CodingKey {
        case headline, ifNothingChanges = "if_nothing_changes", futureSelves = "future_selves", whatItMeans = "what_it_means"
        case bestChange = "best_change", watchOut = "watch_out", tradeOff = "trade_off", comparison, disclaimer
    }
}

struct ActionsOutput: Decodable, Sendable {
    struct AdvisorMeeting: Decodable, Sendable {
        var topics: [String]?
        var sentence: String?
    }

    var intro: String?
    var actions: [AgentAction] = []
    var advisorMeeting: AdvisorMeeting?
    var disclaimer: String?

    private enum CodingKeys: String, CodingKey { case intro, actions, advisorMeeting = "advisor_meeting", disclaimer }
}

struct AgentAction: Decodable, Identifiable, Sendable {
    struct Impact: Decodable, Sendable {
        var chanceNow: String?
        var chanceAfter: String?
        var goalChange: String?
        var monthly: String?
        var perYear: String?
        var overHorizon: String?
        var effectLabel: String?

        private enum CodingKeys: String, CodingKey {
            case chanceNow = "main_goal_chance_now", chanceAfter = "main_goal_chance_after", goalChange = "main_goal_change"
            case monthly, perYear = "per_year", overHorizon = "over_horizon", effectLabel = "effect_label"
        }
    }

    let actionID: String
    let bucket: String
    let title: String
    var why: String?
    var how: String?
    var verifiedBy: String?
    var effort: String?
    var impact: Impact?

    var id: String { actionID }
    private enum CodingKeys: String, CodingKey { case actionID = "action_id", bucket, title, why, how, verifiedBy = "verified_by", effort, impact }
}

struct ActionMapping: Decodable, Sendable {
    struct BackendAction: Decodable, Sendable {
        let id: String
        let title: String
        var monthlyAmount: Double?
        var oneOffAmount: Double?
    }

    var backendActionId: String?
    var canCommit: Bool = false
    var action: BackendAction?
    var reason: String?
}

struct StormResult: Decodable, Sendable {
    let recovers: Bool
    let leanDegrees: Double
    var portfolioDrop: Double?
    let message: String
}
