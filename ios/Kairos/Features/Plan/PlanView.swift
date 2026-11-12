import SwiftUI

/// The third tab: the action agent's plan, what the customer committed to, and their life projects.
struct PlanView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var addingProject = false

    private static let buckets = ["this_week", "this_month", "with_your_advisor"]
    static let bookingLink = URL(string: "https://calendly.com/ouerfelliyassine19/deutsche-bank")

    var body: some View {
        ScrollView {
            if let workspace = model.workspace {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    if let intro = workspace.prediction.actions?.output?.intro {
                        CoachLine(text: intro, mood: .smile, size: 52)
                            .tintTile()
                    }
                    commitments(workspace)
                    ForEach(Self.buckets, id: \.self) { bucket in
                        let actions = workspace.agentActions.filter { $0.bucket == bucket && workspace.tracked($0) == nil }
                        if let first = actions.first {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionHeader(LocalizedStringKey(first.bucketTitle))
                                ForEach(actions) { action in
                                    Button { router.action = action } label: { StepRow(action: action) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    advisor(workspace)
                    projects(workspace)
                }
                .padding(.horizontal, Spacing.screenSide)
                .padding(.top, 4)
                .padding(.bottom, 32)
            }
        }
        .refreshable { await model.refresh() }
        .screenBackground()
        .navigationTitle("Plan")
        .toolbarTitleDisplayMode(.large)
        .sheet(isPresented: $addingProject) { AddProjectSheet() }
    }

    @ViewBuilder private func commitments(_ workspace: Workspace) -> some View {
        let active = workspace.activeCommitments
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Your commitments", trailing: Text(Format.month(workspace.progress.month)))
            if active.isEmpty {
                Text("Commit to a step and your bank data will show whether it happened.")
                    .appFont(15, relativeTo: .subheadline, lineHeight: 1.35)
                    .foregroundStyle(Color.textMuted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(active.enumerated()), id: \.element.id) { index, tracked in
                        HStack(alignment: .top, spacing: 12) {
                            Icon(tracked.status == "VERIFIED" ? "circle-check" : "circle", size: 22)
                                .environment(\.inkColor, tracked.status == "VERIFIED" ? Color.accent : Color.textMuted)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tracked.title).appFont(16, .medium, relativeTo: .callout).foregroundStyle(Color.ink)
                                Text(tracked.evidence ?? (tracked.status == "VERIFIED" ? "Verified by your bank data" : "Committed, waiting for your bank data"))
                                    .appFont(13, relativeTo: .footnote)
                                    .foregroundStyle(Color.textMuted)
                            }
                            Spacer(minLength: 8)
                            Button("Drop") { Task { await model.drop(tracked) } }
                                .buttonStyle(.text)
                        }
                        .padding(.vertical, 10)
                        if index < active.count - 1 { Hairline() }
                    }
                }
                .tile(padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12))
            }
            Button(model.busy ? "Reading your accounts" : "Advance one demo month") { Task { await model.advanceMonth() } }
                .buttonStyle(.secondary)
                .disabled(model.busy)
            Text(model.isLive ? "Demo control: simulates a month of bookings and checks your commitments." : "Saved copy: start the backend to commit and to advance a month.")
                .appFont(13, relativeTo: .footnote)
                .foregroundStyle(Color.textMuted)
        }
    }

    @ViewBuilder private func advisor(_ workspace: Workspace) -> some View {
        if let sentence = workspace.prediction.actions?.output?.advisorMeeting?.sentence {
            VStack(alignment: .leading, spacing: 12) {
                Text(sentence)
                    .appFont(15, relativeTo: .subheadline, lineHeight: 1.4)
                    .foregroundStyle(Color.textSecondary)
                if let link = Self.bookingLink {
                    Link(destination: link) {
                        HStack(spacing: 8) {
                            Icon("calendar-plus", size: 18).environment(\.inkColor, .white)
                            Text("Book a call")
                        }
                    }
                    .buttonStyle(.primaryCompact)
                }
            }
            .tile()
        }
    }

    private func projects(_ workspace: Workspace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Life projects")
            ForEach(workspace.projects) { project in
                let share = project.targetAmount > 0 ? min(project.savedAmount / project.targetAmount, 1) : 0
                HStack(spacing: 14) {
                    Image(HomeView.illustration(for: project.type)).resizable().scaledToFit().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.name).appFont(16, .semibold, relativeTo: .callout).foregroundStyle(Color.ink)
                        Text("\(Format.euro(project.savedAmount)) of \(Format.euro(project.targetAmount))\(project.targetDate.map { ", by \(Format.month($0))" } ?? "")")
                            .appFont(13, relativeTo: .footnote)
                            .foregroundStyle(Color.textMuted)
                        ProgressView(value: share).tint(.accent)
                    }
                }
                .tile(padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14))
            }
            Button {
                addingProject = true
            } label: {
                HStack(spacing: 8) {
                    Icon("plus", size: 18)
                    Text("Add a project")
                }
            }
            .buttonStyle(.secondary)
        }
    }
}

/// One step of the plan: why, what it changes, how it is checked, and the commitment.
struct ActionSheet: View {
    let action: AgentAction
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var committed = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 14) {
                    Mascot(mood: .curious, size: 64, enters: 0.1)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(action.title)
                            .font(.display(22))
                            .foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text([action.bucketTitle, action.effort].compactMap { $0 }.joined(separator: ", "))
                            .appFont(14, relativeTo: .subheadline)
                            .foregroundStyle(Color.textMuted)
                    }
                }
                .padding(.top, 28)
                if let why = action.why {
                    Text(why)
                        .appFont(17, lineHeight: 1.4)
                        .foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let impact = action.impact, let now = impact.chanceNow, let after = impact.chanceAfter {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Chance of reaching your main goal")
                            .appFont(14, relativeTo: .subheadline)
                            .foregroundStyle(Color.textMuted)
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(now).font(.display(28)).foregroundStyle(Color.textMuted)
                            Icon("arrow-right", size: 16).environment(\.inkColor, .textMuted)
                            Text(after).font(.display(28)).foregroundStyle(Color.ink)
                            Spacer(minLength: 4)
                            if let effect = action.effect { Badge(text: effect).fixedSize().layoutPriority(1) }
                        }
                        let facts = [("A month", impact.monthly), ("A year", impact.perYear), ("Over the years", impact.overHorizon)].compactMap { pair in pair.1.map { Fact(label: pair.0, value: $0) } }
                        if !facts.isEmpty { FactList(facts: facts) }
                    }
                    .tile()
                }
                if let film = Explainer.before(action) {
                    ExplainerRow(explainer: film)
                }
                if let how = action.how {
                    block("How", how)
                }
                if let check = action.verifiedBy {
                    block("How it is checked", check)
                }
                commitment
                if let disclaimer = model.workspace?.prediction.actions?.output?.disclaimer {
                    Text(disclaimer)
                        .appFont(13, relativeTo: .footnote)
                        .foregroundStyle(Color.textMuted)
                }
            }
            .padding(.horizontal, Spacing.pageSide)
            .padding(.bottom, 24)
        }
        .presentationBackground(Color.appBackground)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: committed)
    }

    private func block(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).appFont(16, .semibold, relativeTo: .callout).foregroundStyle(Color.ink)
            Text(text)
                .appFont(15, relativeTo: .subheadline, lineHeight: 1.4)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var commitment: some View {
        let workspace = model.workspace
        let mapping = workspace?.actionMappings[action.actionID]
        if let tracked = workspace?.tracked(action) {
            HStack(spacing: 10) {
                Icon("circle-check", size: 22).environment(\.inkColor, Color.accent)
                Text(tracked.status == "VERIFIED" ? "Verified by your bank data" : "You committed to this")
                    .appFont(16, .medium, relativeTo: .callout)
                    .foregroundStyle(Color.ink)
            }
        } else if let mapping, mapping.canCommit, let backend = mapping.action {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your tree tracks it as: \(backend.title.prefix(1).lowercased() + backend.title.dropFirst()).")
                    .appFont(14, relativeTo: .subheadline)
                    .foregroundStyle(Color.textMuted)
                Button(model.busy ? "Committing" : "Commit to this") {
                    Task {
                        await model.commit(action)
                        if model.workspace?.tracked(action) != nil {
                            committed += 1
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.primary)
                .disabled(model.busy)
            }
        } else if action.needsAdvisor, let link = PlanView.bookingLink {
            Link(destination: link) { Text("Book a call with your advisor") }
                .buttonStyle(.primary)
        } else {
            Text("This step is advice. There is nothing for the tree to track.")
                .appFont(14, relativeTo: .subheadline)
                .foregroundStyle(Color.textMuted)
        }
    }
}

/// A new life project, saved to the backend as a bough of the tree.
struct AddProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = "HOME"
    @State private var target = 20_000.0
    @State private var date = Calendar.current.date(byAdding: .year, value: 2, to: .now) ?? .now

    private static let types = [("HOME", "Home"), ("CAR", "Car"), ("TRAVEL", "Travel"), ("BUSINESS", "Business"), ("EDUCATION", "Studies"), ("OTHER", "Something else")]

    var body: some View {
        NavigationStack {
            Form {
                TextField("What are you saving for?", text: $name)
                Picker("Kind", selection: $type) {
                    ForEach(Self.types, id: \.0) { Text($0.1).tag($0.0) }
                }
                VStack(alignment: .leading) {
                    Text("Target: \(Format.euro(target))")
                    Slider(value: $target, in: 1000...300_000, step: 1000).tint(.accent)
                }
                DatePicker("By", selection: $date, in: Date.now..., displayedComponents: .date)
            }
            .navigationTitle("New project")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let day = date.formatted(.iso8601.year().month().day())
                        Task {
                            await model.saveProject(name: name.trimmingCharacters(in: .whitespaces), type: type, target: target, date: day)
                            dismiss()
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One demo month on: what the backend found when it read the accounts again.
struct ReviewView: View {
    let review: MonthReview
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let before = review.before, after = review.after
        let change = after.tree.overallHealth - before.tree.overallHealth
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Spacer()
                    Mascot(mood: change >= 0 ? .cheer : .curious, size: 120, enters: 0.15)
                    Spacer()
                }
                .padding(.top, 28)
                Text("One month on")
                    .font(.display(30))
                    .foregroundStyle(Color.ink)
                Text("\(Format.month(after.progress.month)). I read your accounts again, and this is what changed.")
                    .appFont(17, lineHeight: 1.4)
                    .foregroundStyle(Color.textSecondary)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 14) {
                        ScoreRing(score: before.tree.overallHealth, size: 56, lineWidth: 6)
                        Icon("arrow-right", size: 16).environment(\.inkColor, .textMuted)
                        ScoreRing(score: after.tree.overallHealth, size: 56, lineWidth: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Financial health").appFont(15, .medium, relativeTo: .subheadline).foregroundStyle(Color.ink)
                            Text(change > 0 ? "\(Format.count(change, "point")) up" : change < 0 ? "\(Format.count(-change, "point")) down" : "unchanged")
                                .appFont(14, relativeTo: .subheadline)
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                    FactList(facts: CategoryID.allCases.map { Fact(label: $0.title, value: "\(before.score($0)) to \(after.score($0))") })
                }
                .tile()
                if !after.progress.latestEvents.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader("What happened")
                        ForEach(Array(after.progress.latestEvents.enumerated()), id: \.offset) { index, event in
                            Text(event)
                                .appFont(15, relativeTo: .subheadline, lineHeight: 1.4)
                                .foregroundStyle(Color.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 9)
                            if index < after.progress.latestEvents.count - 1 { Hairline() }
                        }
                    }
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.primary)
            }
            .padding(.horizontal, Spacing.pageSide)
            .padding(.bottom, 24)
        }
        .presentationBackground(Color.appBackground)
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.success, trigger: after.progress.month)
    }
}
