import SwiftUI

/// Behind the avatar: which customer, where the data comes from, the hand-over to the advisor and to a terminal.
struct ProfileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""

    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.profilePath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionHeader("Demo customer")
                        ForEach(Array(model.users.enumerated()), id: \.element.id) { index, user in
                            Button { Task { await model.select(user.id) } } label: {
                                HStack(spacing: 12) {
                                    ScoreRing(score: user.overallHealth, size: 40, lineWidth: 4)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(user.name)\(user.age.map { ", \($0)" } ?? "")").appFont(16, .medium, relativeTo: .callout).foregroundStyle(Color.ink)
                                        Text(user.situation ?? "")
                                            .appFont(13, relativeTo: .footnote)
                                            .foregroundStyle(Color.textMuted)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 8)
                                    if user.id == model.userID { Icon("check", size: 20) }
                                }
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < model.users.count - 1 { Hairline() }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader("Backend")
                        HStack(spacing: 10) {
                            Icon(model.isLive ? "server" : "wifi-off", size: 20)
                            Text(model.isLive ? "Connected. Commitments and demo months work." : "Not reachable. Showing the saved copy.")
                                .appFont(15, relativeTo: .subheadline)
                                .foregroundStyle(Color.textSecondary)
                        }
                        HStack(spacing: 10) {
                            TextField("http://localhost:8080", text: $address)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .appFont(15, relativeTo: .subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.recessed(Color.well), in: RoundedRectangle(cornerRadius: Radius.input, style: .continuous))
                            Button("Connect") {
                                model.baseURL = address
                                Task { await model.refresh() }
                            }
                            .buttonStyle(.secondarySmall)
                        }
                    }
                    VStack(spacing: 0) {
                        NavigationLink(value: Route.advisor) {
                            Row(title: "Summary for your advisor", leading: { Icon("file-text", size: 20) }, trailing: { Chevron() })
                        }
                        .buttonStyle(.plain)
                        Hairline()
                        NavigationLink(value: Route.terminalCode) {
                            Row(title: "Continue from a terminal", leading: { Icon("qr-code", size: 20) }, trailing: { Chevron() })
                        }
                        .buttonStyle(.plain)
                    }
                    VStack(spacing: 12) {
                        Button("Reset the demo data") {
                            Task { await model.resetDemo() }
                        }
                        .buttonStyle(.secondary)
                        .disabled(!model.isLive || model.busy)
                        Button("Show the welcome again") {
                            dismiss()
                            model.startOver()
                        }
                        .buttonStyle(.secondary)
                        Text("Demo customers from the team's backend. No real bank connection.")
                            .appFont(13, relativeTo: .footnote)
                            .foregroundStyle(Color.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, Spacing.screenSide)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Profile")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Icon("x", size: 20) }
                        .accessibilityLabel("Close")
                }
            }
            .routes()
        }
        .presentationBackground(Color.appBackground)
        .onAppear { address = model.baseURL }
        .sensoryFeedback(.selection, trigger: model.userID)
    }
}

/// One page for the human advisor: what the agents found and what the conversation should cover.
struct AdvisorSummaryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            if let workspace = model.workspace {
                let meeting = workspace.prediction.actions?.output?.advisorMeeting
                VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("\(workspace.tree.name)\(model.user?.age.map { ", \($0)" } ?? "")")
                            .appFont(19, .semibold, relativeTo: .title3)
                            .foregroundStyle(Color.ink)
                        Text(model.user?.situation ?? workspace.tree.headline)
                            .appFont(15, relativeTo: .subheadline, lineHeight: 1.35)
                            .foregroundStyle(Color.textMuted)
                        HStack(spacing: 18) {
                            ScoreRing(score: workspace.tree.overallHealth, size: 70, lineWidth: 8)
                            ForEach(CategoryID.allCases) { category in
                                VStack(spacing: 6) {
                                    ScoreRing(score: workspace.score(category), size: 46, lineWidth: 5)
                                    Text(category.title).appFont(12, relativeTo: .caption1).foregroundStyle(Color.textMuted)
                                }
                            }
                        }
                    }
                    .tile()
                    if !workspace.assessment.findings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader("What stands out")
                            ForEach(Array(workspace.assessment.findings.prefix(4).enumerated()), id: \.offset) { index, finding in
                                Text(finding)
                                    .appFont(15, relativeTo: .subheadline, lineHeight: 1.4)
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 10)
                                if index < min(workspace.assessment.findings.count, 4) - 1 { Hairline() }
                            }
                        }
                    }
                    if let sentence = meeting?.sentence {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader("For the conversation")
                            Text(sentence)
                                .appFont(15, relativeTo: .subheadline, lineHeight: 1.4)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                    if !workspace.activeCommitments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeader("Already under way")
                            ForEach(workspace.activeCommitments) { tracked in
                                Row(title: tracked.title, subtitle: tracked.status == "VERIFIED" ? "Verified" : "Committed")
                            }
                        }
                    }
                    if let link = PlanView.bookingLink {
                        Link(destination: link) { Text("Book a call") }
                            .buttonStyle(.primary)
                    }
                    Text("Your advisor sees this page, not your bookings.")
                        .appFont(13, relativeTo: .footnote)
                        .foregroundStyle(Color.textMuted)
                }
                .padding(.horizontal, Spacing.screenSide)
                .padding(.bottom, 32)
            }
        }
        .screenBackground()
        .navigationTitle("For your advisor")
        .toolbarTitleDisplayMode(.inline)
    }
}
