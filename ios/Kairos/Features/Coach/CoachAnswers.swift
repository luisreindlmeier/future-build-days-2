import Foundation

struct CoachReply: Sendable {
    enum Link: Sendable, Equatable { case action(String), category(CategoryID), prediction, tree, advisor }

    var text: String
    var links: [Link] = []
    var mood: Mood = .smile
}

/// The coach's answers. Each one is put together from what the backend and its agents returned for this customer,
/// so the coach says nothing the team's numbers do not back.
enum CoachAnswers {
    static let suggestions = [
        "What should I do first?",
        "What happens if nothing changes?",
        "What should I watch out for?",
        "How is my health calculated?",
        "How do I compare with others?",
        "Tell me about my tree",
    ]

    static func greeting(_ w: Workspace) -> String {
        "Hi \(w.tree.name). Your financial health is \(w.tree.overallHealth) of 100. \(w.tree.headline). Ask me anything about it."
    }

    static func reply(to question: String, in w: Workspace) -> CoachReply {
        let q = question.lowercased()
        func has(_ words: String...) -> Bool { words.contains { q.contains($0) } }
        let forecast = w.forecast

        if has("which etf", "which fund", "which stock", "which share", "should i buy", "should i sell", "recommend a", "best etf", "best fund") {
            return CoachReply(text: "I explain and simulate with your figures, but I do not recommend single products. That is your advisor's part. I can pass on what I found so you do not start from zero.", links: [.advisor], mood: .idle)
        }
        if has("first", "priority", "what should i do", "next step", "where do i start", "improve") {
            guard let first = w.agentActions.first(where: { w.tracked($0) == nil }) else {
                return CoachReply(text: "You have committed to everything on your plan. Now it is about keeping it up.", mood: .happy)
            }
            return CoachReply(text: "Start here: \(first.title.prefix(1).lowercased() + first.title.dropFirst()). \(first.why ?? "")", links: [.action(first.actionID)], mood: .wink)
        }
        if has("nothing changes", "same habits", "carry on", "keep going", "future", "outlook", "prediction") {
            let text = [forecast?.headline, forecast?.ifNothingChanges].compactMap { $0 }.joined(separator: " ")
            return CoachReply(text: text.isEmpty ? "Your outlook is still being prepared." : text, links: [.prediction], mood: .curious)
        }
        if has("watch out", "risk", "worst", "crash", "storm", "afraid", "danger") {
            return CoachReply(text: forecast?.watchOut?.sentence ?? "I see no single risk that stands out.", links: [.prediction, .tree], mood: .curious)
        }
        if has("best change", "single change", "biggest", "most effect", "helps most") {
            let best = forecast?.bestChange
            let text = [best?.why, best?.firstStep.map { "First step: \($0)" }].compactMap { $0 }.joined(separator: " ")
            return CoachReply(text: text.isEmpty ? "I have no single best change for you yet." : text, links: [.prediction], mood: .wink)
        }
        if has("calculat", "how is my", "health work", "score work", "method", "measured") {
            let a = w.assessment
            let percentile = w.tree.wellbeing?.percentile.map { "You are at the \(Format.number($0, decimals: 0))th percentile of your age group. " } ?? ""
            return CoachReply(text: "Half of your financial health is how you are doing on the CFPB well-being scale. \(percentile)The other half is what your bank data shows: spending \(a.spendScore), saving \(a.savingsScore), investing \(a.investScore) and knowledge \(a.knowledgeScore). Together that makes \(w.tree.overallHealth).", mood: .idle)
        }
        if has("compare", "others", "peers", "my age", "average", "normal") {
            let worst = w.tree.leaves.filter { $0.health != "HEALTHY" }.max { $0.size < $1.size }
            let percentile = w.tree.wellbeing?.percentile.map { "On financial well-being you are at the \(Format.number($0, decimals: 0))th percentile of people aged \(w.tree.wellbeing?.ageBand ?? "like you"). " } ?? ""
            return CoachReply(text: percentile + (worst.map { "On spending, \($0.label.lowercased()) stands out: \($0.detail)" } ?? "Your spending is in line with households like yours."), links: [.category(.spending)], mood: .smile)
        }
        if has("tree", "leaves", "roots", "trunk", "soil") {
            return CoachReply(text: "\(w.tree.headline). The leaves are what you spend, the trunk is what you invest, the roots are what you have set aside, and the soil is your confidence with money. Tap any part to see what I found.", links: [.tree], mood: .happy)
        }
        if has("advisor", "human", "a person", "appointment", "call") {
            return CoachReply(text: w.prediction.actions?.output?.advisorMeeting?.sentence ?? "I can hand you over to your advisor with a summary of what I found.", links: [.advisor], mood: .smile)
        }
        if has("project", "home", "flat", "house", "saving for") {
            guard let branch = w.tree.branches.first else { return CoachReply(text: "You have no project yet. Add one under Plan and it becomes a bough of your tree.", mood: .idle) }
            return CoachReply(text: "\(branch.name): \(branch.detail)", links: [.tree], mood: .curious)
        }
        if let category = CategoryID.allCases.first(where: { q.contains($0.rawValue) || q.contains(String($0.rawValue.dropLast(3))) }) {
            return CoachReply(text: "\(category.title) is at \(w.score(category)). \(w.summary(category))", links: [.category(category)], mood: .curious)
        }
        if has("hi", "hello", "hey", "thanks", "thank you") {
            return CoachReply(text: "Happy to help. Ask me about your health, your tree or what to do first.", mood: .happy)
        }
        return CoachReply(text: "I can tell you about your financial health, your tree, your outlook and what to do first. For anything about single products, your advisor is the right person.", mood: .idle)
    }
}
