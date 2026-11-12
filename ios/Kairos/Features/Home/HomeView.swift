import SwiftUI

/// The first tab: financial health with its three rings, what is under way, what stands out and the next steps.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        ScrollViewReader { proxy in
            page.task { await DebugLaunch.showFilms(with: proxy) }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let workspace = model.workspace {
                    ScoreHero(workspace: workspace) { router.homePath = [.category($0)] }
                    tiles(workspace)
                    outlook(workspace)
                    noticed(workspace)
                    steps(workspace)
                    ExplainerShelf(title: "Explained in two minutes", explainers: Explainer.picks(for: workspace))
                        .id("films")
                }
            }
            .padding(.horizontal, Spacing.screenSide)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
        .refreshable { await model.refresh() }
        .screenBackground()
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { router.profileOpen = true } label: {
                    Text(String(model.workspace?.tree.name.prefix(1) ?? ""))
                        .appFont(16, .semibold, relativeTo: .callout)
                        .foregroundStyle(Color.white)
                        .frame(width: 38, height: 38)
                        .background { BrandSurface().clipShape(Circle()) }
                        .overlay { Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 2) }
                        .shadow(color: Color.brand.opacity(0.22), radius: 5, y: 3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .principal) {
                Text(model.workspace.map { Format.month($0.progress.month) } ?? "")
                    .appFont(14, .medium, relativeTo: .subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func tiles(_ workspace: Workspace) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button { router.tab = .plan } label: {
                let project = workspace.projects.first
                let share = project.map { $0.targetAmount > 0 ? $0.savedAmount / $0.targetAmount : 0 } ?? 0
                InfoTile(title: project?.name ?? "No project yet", line: project == nil ? "Add what you are saving for" : "\(Format.percent(share)) funded",
                         done: Int((share * 6).rounded(.down)), total: 6) {
                    Image(project.map { Self.illustration(for: $0.type) } ?? "illustration-saving").resizable().scaledToFit().frame(height: 40)
                }
            }
            .buttonStyle(.plain)
            Button { router.tab = .plan } label: {
                let active = workspace.activeCommitments
                let verified = active.filter { $0.status == "VERIFIED" }.count
                InfoTile(title: active.isEmpty ? "No commitment yet" : Format.count(active.count, "commitment"),
                         line: active.isEmpty ? "Pick a next step" : "\(verified) verified by your bank data", done: verified, total: max(active.count, 1)) {
                    Icon("target", size: 28).frame(height: 40)
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func outlook(_ workspace: Workspace) -> some View {
        if let headline = workspace.forecast?.headline {
            NavigationLink(value: Route.prediction) {
                HStack(spacing: 12) {
                    Icon("chart-line", size: 22)
                        .environment(\.inkColor, .accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Your outlook").appFont(16, .semibold, relativeTo: .callout).foregroundStyle(Color.ink)
                        Text(headline)
                            .appFont(14, relativeTo: .subheadline, lineHeight: 1.35)
                            .foregroundStyle(Color.textMuted)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Chevron()
                }
                .tintTile(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 14))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func noticed(_ workspace: Workspace) -> some View {
        let findings = workspace.assessment.findings.prefix(3)
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("The coach noticed")
                VStack(spacing: 0) {
                    ForEach(Array(findings.enumerated()), id: \.offset) { index, finding in
                        Text(finding)
                            .appFont(15, relativeTo: .subheadline, lineHeight: 1.35)
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 13)
                        if index < findings.count - 1 { Hairline() }
                    }
                }
                .tile(padding: EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
            }
        }
    }

    @ViewBuilder private func steps(_ workspace: Workspace) -> some View {
        let actions = workspace.agentActions.filter { workspace.tracked($0) == nil }
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Next steps")
                ForEach(actions.prefix(4)) { action in
                    Button { router.action = action } label: { StepRow(action: action) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    static func illustration(for projectType: String) -> String {
        switch projectType {
        case "HOME": "illustration-firstHome"
        case "BUSINESS": "illustration-business"
        default: "illustration-saving"
        }
    }
}

/// Financial health on the navy block: the number, the coach, and the three categories as rings.
struct ScoreHero: View {
    let workspace: Workspace
    let open: (CategoryID) -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your financial health")
                        .appFont(15, .medium, relativeTo: .subheadline)
                        .foregroundStyle(Color.onBrandMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        CountUp(value: workspace.tree.overallHealth, font: .system(size: 64, weight: .bold))
                            .onBrand()
                        Text("of 100")
                            .appFont(15, relativeTo: .subheadline)
                            .foregroundStyle(Color.onBrandMuted)
                    }
                    Text(workspace.tree.headline)
                        .appFont(14, relativeTo: .subheadline, lineHeight: 1.35)
                        .foregroundStyle(Color.white.opacity(0.86))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                Spacer(minLength: 8)
                Mascot(mood: workspace.tree.overallHealth >= 40 ? .smile : .idle, size: 104)
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            HStack(alignment: .top, spacing: 0) {
                ForEach(CategoryID.allCases) { category in
                    Button { open(category) } label: {
                        VStack(spacing: 10) {
                            ScoreRing(score: workspace.score(category), size: 84, lineWidth: 8, onBrand: true)
                            HStack(spacing: 1) {
                                Text(category.title)
                                    .appFont(14, .semibold, relativeTo: .subheadline)
                                    .onBrand()
                                Icon("chevron-right", size: 15)
                                    .environment(\.inkColor, .white.opacity(0.7))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(20)
        .background { BrandSurface() }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct InfoTile<Top: View>: View {
    let title: String
    let line: String
    let done: Int
    let total: Int
    @ViewBuilder var top: Top

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                top
                Spacer()
                Chevron()
            }
            Text(title)
                .appFont(15, .semibold, relativeTo: .subheadline)
                .foregroundStyle(Color.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
            Text(line)
                .appFont(13, relativeTo: .footnote)
                .foregroundStyle(Color.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            StepsBar(done: done, total: total)
        }
        .tile(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
    }
}

/// Progress in whole steps: so many of so many.
struct StepsBar: View {
    let done: Int
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < done ? Color.accent : Color.track)
                    .frame(height: 4)
            }
        }
        .padding(.top, 2)
        .accessibilityHidden(true)
    }
}

/// A next step in a list: the drawing of its category, what to do, what it is worth.
struct StepRow: View {
    let action: AgentAction

    var body: some View {
        HStack(spacing: 14) {
            Image(action.category.illustration)
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(action.title)
                    .appFont(16, .semibold, relativeTo: .callout)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.leading)
                if let effect = action.effect { Badge(text: effect) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Chevron()
        }
        .tile(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
    }
}
