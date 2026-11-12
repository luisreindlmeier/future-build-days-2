import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var router = Router()
    @State private var prepared = false

    private var isTerminal: Bool {
        DebugLaunch.terminal || UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        @Bindable var model = model
        Group {
            if isTerminal {
                TerminalView()
            } else if !model.onboardingDone {
                OnboardingView()
                    .transition(.opacity)
            } else {
                MainTabs()
                    .transition(.opacity)
            }
        }
        .environment(router)
        .screenBackground()
        .animation(.easeInOut(duration: 0.4), value: model.onboardingDone)
        .task {
            guard !prepared else { return }
            prepared = true
            DebugLaunch.apply(to: router, model: model)
            if !DebugLaunch.offline {
                await model.refresh()
                DebugLaunch.apply(to: router, model: model)
            }
            if DebugLaunch.value("-do") == "commit", let workspace = model.workspace,
               let action = workspace.agentActions.first(where: { workspace.actionMappings[$0.actionID]?.canCommit == true }) {
                await model.commit(action)
                await model.advanceMonth()
            }
        }
        .alert("Kairos", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }
}

struct MainTabs: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Home", image: "lucide-house", value: AppTab.home) {
                NavigationStack(path: $router.homePath) {
                    HomeView().routes()
                }
            }
            Tab("Tree", image: "lucide-tree-deciduous", value: AppTab.tree) {
                NavigationStack {
                    TreeView()
                }
            }
            Tab("Plan", image: "lucide-flag", value: AppTab.plan) {
                NavigationStack(path: $router.planPath) {
                    PlanView().routes()
                }
            }
            Tab("Coach", image: "lucide-message-circle", value: AppTab.coach) {
                NavigationStack {
                    CoachView()
                }
            }
        }
        .tint(.accent)
        .sheet(item: $router.action) { action in
            ActionSheet(action: action)
        }
        .sheet(item: $router.area) { selection in
            AreaSheet(selection: selection)
        }
        .sheet(item: $router.film) { film in
            ExplainerSheet(explainer: film)
        }
        .sheet(isPresented: $router.profileOpen) {
            ProfileSheet()
        }
        .sheet(isPresented: Binding(get: { model.review != nil }, set: { if !$0 { model.review = nil } })) {
            if let review = model.review { ReviewView(review: review) }
        }
    }
}

extension View {
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case let .category(id): CategoryView(id: id)
            case .prediction: PredictionView()
            case .advisor: AdvisorSummaryView()
            case .terminalCode: TerminalCodeView()
            }
        }
    }
}
