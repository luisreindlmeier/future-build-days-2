import SwiftUI

/// One of the three categories: a large ring, then its parts of the tree as rows, then the coach.
struct CategoryView: View {
    let id: CategoryID
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        ScrollViewReader { proxy in
            page.task { await DebugLaunch.showFilms(with: proxy) }
        }
    }

    private var page: some View {
        ScrollView {
            if let workspace = model.workspace {
                let areas = workspace.areas(id)
                VStack(spacing: 22) {
                    ScoreRing(score: workspace.score(id), size: 212, lineWidth: 15, caption: id.title)
                        .padding(.top, 8)
                    Text(id.question)
                        .appFont(16, lineHeight: 1.35)
                        .foregroundStyle(Color.textMuted)
                        .multilineTextAlignment(.center)
                    VStack(spacing: 0) {
                        ForEach(Array(areas.enumerated()), id: \.element.id) { index, area in
                            Button { router.area = AreaSelection(category: id, area: area) } label: {
                                HStack(spacing: 12) {
                                    Icon(area.icon, size: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(area.title).appFont(16, .medium, relativeTo: .callout).foregroundStyle(Color.ink)
                                        Text(area.word).appFont(13, relativeTo: .footnote).foregroundStyle(Color.textMuted)
                                    }
                                    Spacer(minLength: 8)
                                    HealthBar(health: area.health)
                                    Chevron()
                                }
                                .padding(.vertical, 13)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < areas.count - 1 { Hairline() }
                        }
                    }
                    .tile(padding: EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 12))
                    CoachLine(text: workspace.summary(id), mood: .smile, size: 48)
                        .tintTile()
                    let actions = workspace.agentActions.filter { $0.category == id && workspace.tracked($0) == nil }
                    if !actions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader("What would help")
                            ForEach(actions.prefix(3)) { action in
                                Button { router.action = action } label: { StepRow(action: action) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    ExplainerShelf(title: "Explained in two minutes", explainers: Explainer.about(id))
                        .id("films")
                }
                .padding(.horizontal, Spacing.screenSide)
                .padding(.bottom, 32)
            }
        }
        .screenBackground()
        .navigationTitle(id.title)
        .toolbarTitleDisplayMode(.inline)
    }
}

/// One part of a category: its state, what the backend found and the figures behind it.
struct AreaSheet: View {
    let selection: AreaSelection
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let area = selection.area
        FittedSheet {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Icon(area.icon, size: 24)
                    Text(area.title).font(.display(24)).foregroundStyle(Color.ink)
                }
                HStack(spacing: 10) {
                    HealthChip(health: area.health, text: area.word)
                    HealthBar(health: area.health, segment: CGSize(width: 26, height: 6))
                }
                Text(area.detail)
                    .appFont(17, lineHeight: 1.4)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !area.facts.isEmpty {
                    FactList(facts: area.facts)
                        .tile(padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
                if let film = Explainer.about(area, in: selection.category) {
                    ExplainerRow(explainer: film, lead: "Explained")
                }
                if let id = area.actionID, let action = model.workspace?.agentActions.first(where: { $0.actionID == id }) {
                    Button("See the step for this") {
                        dismiss()
                        router.action = action
                    }
                    .buttonStyle(.primary)
                }
            }
            .padding(.horizontal, Spacing.pageSide)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
    }
}
