import SwiftUI

/// The first run: say hello, pick the demo customer, agree what is read, watch the check, see the result.
struct OnboardingView: View {
    enum Step: Int { case welcome, customer, consent, scan, reveal, findings }

    @Environment(AppModel.self) private var model
    @State private var step: Step = OnboardingView.firstStep
    @State private var taps = 0
    @State private var greeting: Mood = .smile

    private static var firstStep: Step {
        switch DebugLaunch.screen {
        case "onboarding-customer": .customer
        case "onboarding-consent": .consent
        case "onboarding-scan": .scan
        case "onboarding-reveal": .reveal
        case "onboarding-findings": .findings
        default: .welcome
        }
    }

    var body: some View {
        ZStack {
            switch step {
            case .welcome: welcome
            case .customer: CustomerPicker(title: "Who is checking in?", button: "Continue") { go(.consent) }
            case .consent: ConsentView(button: "Check my finances") { go(.scan) }
            case .scan: ScanView(steps: model.workspace?.scanSteps ?? []) { go(.reveal) }
            case .reveal: RevealView { go(.findings) }
            case .findings: findings
            }
        }
        .padding(.horizontal, Spacing.pageSide)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .sensoryFeedback(.soft, trigger: taps)
    }

    private func go(_ next: Step) {
        taps += 1
        withAnimation(.easeInOut(duration: 0.35)) { step = next }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Mascot(mood: greeting, size: 170, enters: 0.25)
            Text("Kairos")
                .font(.display(40))
                .foregroundStyle(Color.ink)
                .padding(.top, 28)
                .rises(after: 0.6)
            Text("A check-up for your money.")
                .appFont(18)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, 6)
                .rises(after: 0.75)
            Spacer()
            Spacer()
            Text("Deutsche Bank hackathon concept. I am an AI coach: I explain and simulate. For product advice I bring in your advisor.")
                .appFont(13, relativeTo: .footnote)
                .foregroundStyle(Color.textMuted)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
                .rises(after: 0.95)
            Button("Start my check-up") { go(.customer) }
                .buttonStyle(.primary)
                .padding(.bottom, 12)
                .rises(after: 1.05)
        }
        .transition(.opacity)
        .task {
            // The coach says hello, then keeps changing its face now and then.
            let hello: [(Mood, Int)] = [(.cheer, 1500), (.wink, 1700), (.smile, 1300)]
            for (mood, wait) in hello {
                try? await Task.sleep(for: .milliseconds(wait))
                greeting = mood
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(4200))
                greeting = [Mood.happy, .cheer, .wink, .smile].filter { $0 != greeting }.randomElement() ?? .smile
            }
        }
    }

    private var findings: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What I found")
                .font(.display(30))
                .foregroundStyle(Color.ink)
                .padding(.top, 48)
                .padding(.bottom, 20)
            if let workspace = model.workspace {
                VStack(spacing: 12) {
                    ForEach(Array(workspace.assessment.findings.prefix(3).enumerated()), id: \.offset) { index, finding in
                        HStack(alignment: .top, spacing: 14) {
                            Mascot(mood: [Mood.curious, .idle, .wink][index % 3], size: 48, enters: 0.2 + 0.18 * Double(index))
                            Text(finding)
                                .appFont(16, lineHeight: 1.4)
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tile()
                        .rises(after: 0.1 + 0.18 * Double(index))
                    }
                }
            }
            Spacer()
            Button("Open my check-up") { model.onboardingDone = true }
                .buttonStyle(.primary)
                .padding(.bottom, 12)
        }
        .transition(.opacity)
    }
}

/// The four demo customers of the team's backend.
struct CustomerPicker: View {
    let title: String
    let button: String
    var large = false
    let onContinue: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.display(large ? 44 : 30))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: large ? .center : .leading)
                .padding(.top, large ? 40 : 48)
                .padding(.bottom, 20)
            ForEach(model.users) { user in
                Button { Task { await model.select(user.id) } } label: {
                    HStack(spacing: 14) {
                        Text(String(user.name.prefix(1)))
                            .appFont(large ? 22 : 17, .semibold)
                            .foregroundStyle(Color.brand)
                            .frame(width: large ? 56 : 44, height: large ? 56 : 44)
                            .background(Color.brandTint, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(user.name)\(user.age.map { ", \($0)" } ?? "")").appFont(large ? 22 : 17, .medium).foregroundStyle(Color.ink)
                            Text(user.situation ?? "")
                                .appFont(large ? 16 : 14, relativeTo: .subheadline)
                                .foregroundStyle(Color.textMuted)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        Icon(user.id == model.userID ? "circle-check" : "circle", size: large ? 28 : 24)
                            .environment(\.inkColor, user.id == model.userID ? Color.ink : Color.divider)
                    }
                    .padding(.vertical, large ? 16 : 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Hairline()
            }
            Spacer()
            Button(button, action: onContinue)
                .buttonStyle(PrimaryButtonStyle(height: large ? 72 : 52, radius: large ? 16 : Radius.button, fontSize: large ? 22 : 17))
                .padding(.bottom, large ? 36 : 12)
        }
        .sensoryFeedback(.selection, trigger: model.userID)
        .transition(.opacity)
    }
}

/// What the check reads, and the agreement to it.
struct ConsentView: View {
    let button: String
    var large = false
    let onAgree: () -> Void

    private static let scopes = [
        ("credit-card", "Accounts and cards", "Your spending by category, for the leaves."),
        ("piggy-bank", "Savings", "What you have set aside, for the roots."),
        ("trending-up", "Portfolio", "What you have invested, for the trunk."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What I look at")
                .font(.display(large ? 44 : 30))
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: large ? .center : .leading)
                .padding(.top, large ? 40 : 48)
                .padding(.bottom, 16)
            CoachLine(text: "I read this to grow your tree. Nothing leaves the bank, and your figures show on your phone, never on a shared screen.", mood: .idle, size: large ? 72 : 56)
                .padding(.bottom, 12)
            ForEach(Self.scopes, id: \.1) { icon, title, text in
                HStack(spacing: 14) {
                    Icon(icon, size: large ? 28 : 22).frame(width: large ? 40 : 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).appFont(large ? 21 : 17, .medium).foregroundStyle(Color.ink)
                        Text(text).appFont(large ? 16 : 14, relativeTo: .subheadline).foregroundStyle(Color.textMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, large ? 16 : 12)
                Hairline()
            }
            Text("By continuing you agree that Kairos reads these for your check-up. You can withdraw at any time.")
                .appFont(large ? 15 : 13, relativeTo: .footnote)
                .foregroundStyle(Color.textMuted)
                .padding(.top, 14)
            Spacer()
            Button(button, action: onAgree)
                .buttonStyle(PrimaryButtonStyle(height: large ? 72 : 52, radius: large ? 16 : Radius.button, fontSize: large ? 22 : 17))
                .padding(.bottom, large ? 36 : 12)
        }
        .transition(.opacity)
    }
}

/// The check, step by step, with what each step really did for this customer.
struct ScanView: View {
    let steps: [ScanStep]
    var large = false
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reached = 0
    @State private var finished = false

    var body: some View {
        VStack(spacing: 0) {
            Mascot(mood: finished ? .cheer : .curious, size: large ? 200 : 130, motion: finished ? .idle : .looking, enters: 0.1, beat: reached)
                .padding(.top, large ? 24 : 56)
            Text(finished ? "Done" : "Checking")
                .font(.display(large ? 40 : 30))
                .foregroundStyle(Color.ink)
                .padding(.top, 20)
            ProgressView(value: Double(min(reached, steps.count)), total: Double(max(steps.count, 1)))
                .tint(.accent)
                .padding(.top, 14)
                .padding(.bottom, 22)
            VStack(alignment: .leading, spacing: large ? 18 : 14) {
                ForEach(steps.prefix(reached + 1)) { step in
                    HStack(alignment: .top, spacing: 12) {
                        Group {
                            if step.id <= reached || finished {
                                Icon("check", size: large ? 22 : 18)
                            } else {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(step.title).appFont(large ? 20 : 16, .medium).foregroundStyle(Color.ink)
                            Text(step.detail).appFont(large ? 17 : 14, relativeTo: .subheadline).foregroundStyle(Color.textMuted)
                        }
                    }
                    .transition(.opacity.combined(with: .offset(y: 8)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .transition(.opacity)
        .task {
            for index in steps.indices {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 250 : 800))
                withAnimation(.easeOut(duration: 0.3)) { reached = index + 1 }
            }
            withAnimation(.easeOut(duration: 0.3)) { finished = true }
            try? await Task.sleep(for: .milliseconds(650))
            onDone()
        }
        .sensoryFeedback(.selection, trigger: reached)
        .sensoryFeedback(.success, trigger: finished) { _, done in done }
    }
}

/// The first look: financial health, then its three parts.
struct RevealView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            if let workspace = model.workspace {
                ScoreRing(score: workspace.tree.overallHealth, size: 190, lineWidth: 14)
                Text("Your financial health")
                    .appFont(17, .medium)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 18)
                HStack(spacing: 22) {
                    ForEach(CategoryID.allCases) { category in
                        VStack(spacing: 8) {
                            ScoreRing(score: workspace.score(category), size: 62)
                            Text(category.title).appFont(14, .medium, relativeTo: .subheadline).foregroundStyle(Color.ink)
                        }
                    }
                }
                .padding(.top, 30)
                Spacer()
                CoachLine(text: "\(workspace.tree.headline). It is about how well your money works, not how much there is.", mood: .happy)
                    .padding(.bottom, 20)
            }
            Button("See what I found", action: onContinue)
                .buttonStyle(.primary)
                .padding(.bottom, 12)
        }
        .transition(.opacity)
    }
}
