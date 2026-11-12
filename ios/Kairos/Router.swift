import SwiftUI

enum AppTab: Hashable { case home, tree, plan, coach }

enum Route: Hashable {
    case category(CategoryID)
    case prediction
    case advisor
    case terminalCode
}

/// Where the app is: the tab, each tab's stack and what is presented over it.
@Observable
final class Router {
    var tab: AppTab = .home
    var homePath: [Route] = []
    var planPath: [Route] = []
    var profilePath: [Route] = []
    var profileOpen = false
    var action: AgentAction?
    var area: AreaSelection?
    var film: Explainer?

    func openAdvisor() {
        profilePath = [.advisor]
        profileOpen = true
    }
}

struct AreaSelection: Identifiable {
    let category: CategoryID
    let area: Area

    var id: String { category.rawValue + area.id }
}

/// Launch arguments for checks: `-screen <name>` opens one screen, `-terminal` the branch terminal,
/// `-user <id>` picks the customer, `-scroll films` moves Home or a category down to its films.
enum DebugLaunch {
    private static let arguments = ProcessInfo.processInfo.arguments

    static func value(_ flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var screen: String? { value("-screen") }
    static var scrollsToFilms: Bool { value("-scroll") == "films" }
    static var terminal: Bool { arguments.contains("-terminal") || (screen ?? "").hasPrefix("terminal") }
    /// Screens for checks read the saved copy, so they look the same with and without a backend.
    static var offline: Bool { screen != nil && !arguments.contains("-live") }

    /// A design screen starts from a clean slate and leaves the real state alone.
    static var store: UserDefaults {
        guard screen != nil, let scratch = UserDefaults(suiteName: "kairos.screens") else { return .standard }
        scratch.removePersistentDomain(forName: "kairos.screens")
        if let user = value("-user") { scratch.set(user, forKey: "userID") }
        return scratch
    }

    static func apply(to router: Router, model: AppModel) {
        guard let screen else { return }
        if screen.hasPrefix("onboarding") {
            model.onboardingDone = false
            return
        }
        model.onboardingDone = true
        let parts = screen.split(separator: "-", maxSplits: 1).map(String.init)
        let argument = parts.count > 1 ? parts[1] : ""
        switch parts[0] {
        case "category":
            if let id = CategoryID(rawValue: argument) { router.homePath = [.category(id)] }
        case "area":
            if let id = CategoryID(rawValue: argument), let area = model.workspace?.areas(id).first(where: { $0.health != .strong }) {
                router.homePath = [.category(id)]
                router.area = AreaSelection(category: id, area: area)
            }
        case "prediction": router.homePath = [.prediction]
        case "tree": router.tab = .tree
        case "plan": router.tab = .plan
        case "action":
            router.tab = .plan
            router.action = model.workspace?.agentActions.first { argument.isEmpty || $0.actionID == argument }
        case "film": router.film = Explainer.with(argument) ?? Explainer.all.first
        case "coach": router.tab = .coach
        case "profile": router.profileOpen = true
        case "advisor": router.openAdvisor()
        default: break
        }
    }
}

extension DebugLaunch {
    /// For checks and recordings: after a moment, scrolls the page down to its films.
    static func showFilms(with proxy: ScrollViewProxy) async {
        guard scrollsToFilms else { return }
        try? await Task.sleep(for: .milliseconds(Int((Double(value("-scrollAfter") ?? "") ?? 1.2) * 1000)))
        withAnimation(.easeInOut(duration: 1.1)) { proxy.scrollTo("films", anchor: .bottom) }
    }
}
