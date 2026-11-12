import Foundation
import Testing
@testable import Kairos

/// The saved copies are real backend answers, so decoding them checks the app against the team's API.
@MainActor
struct SnapshotTests {
    static let customers = ["lena", "alex", "maya", "max"]

    @Test func everyCustomerDecodes() {
        #expect(Snapshot.users().map(\.id).sorted() == Self.customers.sorted())
        for id in Self.customers {
            let workspace = Snapshot.workspace(id)
            #expect(workspace != nil, "workspace-\(id).json does not decode")
            #expect(workspace?.prediction.status == "READY")
            #expect(Snapshot.storm(id) != nil)
        }
    }

    @Test func theTreeHasItsParts() throws {
        let tree = try #require(Snapshot.workspace("maya")).tree
        #expect(tree.roots.count == 4)
        #expect(tree.leaves.count == 7)
        #expect((0...100).contains(tree.overallHealth))
    }

    @Test func categoriesComeFromTheBankDataScores() throws {
        let workspace = try #require(Snapshot.workspace("maya"))
        #expect(workspace.score(.spending) == workspace.assessment.spendScore)
        #expect(workspace.score(.saving) == workspace.assessment.savingsScore)
        #expect(workspace.score(.investing) == workspace.assessment.investScore)
        #expect(workspace.areas(.spending).count == workspace.tree.leaves.count)
        #expect(workspace.areas(.saving).count == workspace.tree.roots.count)
        #expect(workspace.areas(.investing).count == 4)
    }

    @Test func healthFollowsTheBackendsSteps() {
        #expect(Health(score: 75) == .strong)
        #expect(Health(score: 74) == .growing)
        #expect(Health(score: 40) == .growing)
        #expect(Health(score: 39) == .needsCare)
        #expect(Health(status: "ROTTEN") == .needsCare)
        #expect(Health(status: "MISSING") == .missing)
    }

    @Test func everyActionHasABucketAndAMapping() throws {
        for id in Self.customers {
            let workspace = try #require(Snapshot.workspace(id))
            #expect(!workspace.agentActions.isEmpty)
            for action in workspace.agentActions {
                #expect(["this_week", "this_month", "with_your_advisor"].contains(action.bucket), "\(action.actionID) has bucket \(action.bucket)")
                #expect(workspace.actionMappings[action.actionID] != nil, "\(action.actionID) has no mapping")
            }
        }
    }

    @Test func theChartHasOnePointPerYear() throws {
        let chart = try #require(Snapshot.workspace("alex")?.prediction.chart)
        #expect(chart.todayPath.p50.count == chart.years + 1)
        #expect(chart.byScenario["full_plan"] != nil)
    }

    @Test func theCoachAnswersFromTheAgentsOutput() throws {
        let workspace = try #require(Snapshot.workspace("maya"))
        let first = CoachAnswers.reply(to: "What should I do first?", in: workspace)
        #expect(first.links.contains(.action(workspace.agentActions[0].actionID)))
        let products = CoachAnswers.reply(to: "Which ETF should I buy?", in: workspace)
        #expect(products.links == [.advisor])
    }

    @Test func theTerminalCodeRoundTrips() {
        let handoff = TerminalHandoff(user: "alex")
        #expect(TerminalHandoff(url: handoff.url) == handoff)
        #expect(TerminalHandoff(url: "https://example.com") == nil)
    }
}
