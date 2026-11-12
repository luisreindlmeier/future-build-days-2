import SwiftUI

/// A short film that explains one idea in plain words. The prototype shows its cover and what it covers; the films
/// themselves are not recorded. The topics follow the learning missions of the web dashboard, plus paying later and funds.
struct Explainer: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Minutes and seconds, as on the cover.
    let length: String
    let category: CategoryID
    let art: String
    let points: [String]
}

extension Explainer {
    static let all: [Explainer] = [
        Explainer(id: "pay-later", title: "Buy now, pay later: what it really costs", length: "2:10", category: .spending, art: "illustration-payLater", points: [
            "Splitting a purchase into instalments feels free. It is still a loan, and it lowers what you have left every month until it is paid.",
            "Miss a payment and fees start. Several small plans at once, with Klarna, PayPal or a card, are easy to lose track of.",
            "A simple test: if you would not pay the full price today, the instalments do not make it affordable.",
        ]),
        Explainer(id: "budget", title: "A budget that survives real life", length: "2:20", category: .spending, art: "illustration-budget", points: [
            "Start from what comes in. Rent, bills and savings go first, and what is left is yours to spend.",
            "A common rule of thumb is 50, 30, 20: half for needs, 30 percent for wants, 20 percent for saving and paying off debt.",
            "A monthly limit per category works better than counting every coffee.",
        ]),
        Explainer(id: "subscriptions", title: "Subscriptions: the quiet leak", length: "1:45", category: .spending, art: "illustration-subscriptions", points: [
            "Small monthly charges add up. Twelve euros a month is 144 euros a year.",
            "Go through your account once and keep what you used in the last month.",
            "Cancelling takes minutes, and you can always come back.",
        ]),
        Explainer(id: "safety-net", title: "Your safety net: three months first", length: "2:15", category: .saving, art: "illustration-safetyNet", points: [
            "A buffer keeps one surprise, a repair or a gap in income, from turning into debt.",
            "A common target is three to six months of your fixed costs, in an account you can reach at once.",
            "Build it with a standing order on payday, before the money is spent.",
        ]),
        Explainer(id: "home", title: "Buying a home: what you need before the price", length: "3:10", category: .saving, art: "illustration-firstHome", points: [
            "Banks like to see your own money in the deal. A common guide is 20 percent of the price.",
            "Buying costs come on top: land transfer tax, the notary and often an agent. In Germany that is around a tenth of the price or more.",
            "Your monthly saving decides when it works. A project on your tree shows how far you are.",
        ]),
        Explainer(id: "protect", title: "Protecting your income", length: "2:10", category: .saving, art: "illustration-protect", points: [
            "Your ability to earn is worth more than anything you own.",
            "If illness stopped your income, the state replaces only part of it.",
            "An advisor can show what closing that gap would cost. The coach does not recommend products.",
        ]),
        Explainer(id: "funds", title: "ETFs in three minutes", length: "3:00", category: .investing, art: "illustration-funds", points: [
            "An ETF is a fund that follows an index and trades on the stock exchange like a share.",
            "One ETF on a world index spreads your money over more than a thousand companies.",
            "Costs are low because nobody picks the shares. Prices still go up and down, so it suits money you will not need for years.",
        ]),
        Explainer(id: "compound", title: "How money grows", length: "2:30", category: .investing, art: "illustration-compound", points: [
            "Returns earn returns. The longer money stays invested, the more of the growth comes from that.",
            "100 euros a month for 30 years is 36,000 euros paid in. At 5 percent a year it would grow to roughly 83,000 euros. No return is guaranteed.",
            "Starting early matters more than starting big.",
        ]),
        Explainer(id: "spread", title: "Not all your eggs in one basket", length: "2:20", category: .investing, art: "illustration-spread", points: [
            "One company can fail. A whole market rarely does.",
            "If one position is more than a third of your portfolio, its bad year is your bad year.",
            "Spreading over companies, countries and sectors lowers the swings.",
        ]),
        Explainer(id: "calm", title: "Staying calm in a storm", length: "2:40", category: .investing, art: "illustration-calm", points: [
            "Markets fall sharply every few years. It is part of investing, not a sign that something is broken.",
            "Selling in a fall locks in the loss. Those who stayed invested took part in the recovery.",
            "Write your rules while it is calm: what you will do, and what you will not.",
        ]),
    ]

    static func with(_ id: String) -> Explainer? { all.first { $0.id == id } }

    static func about(_ category: CategoryID) -> [Explainer] { all.filter { $0.category == category } }

    /// The film to watch before a step of the plan.
    static func before(_ action: AgentAction) -> Explainer? {
        switch action.actionID {
        case "limit_eating_out", "limit_shopping": with("budget")
        case "cancel_unused_subscriptions": with("subscriptions")
        case "pause_purchase": with("pay-later")
        case "start_buffer": with("safety-net")
        case "save_more_tomorrow": with("compound")
        case "family_diversification_plan": with("spread")
        case "write_crash_rules": with("calm")
        case "income_protection_check": with("protect")
        default: nil
        }
    }

    /// The film behind one row of a category page.
    static func about(_ area: Area, in category: CategoryID) -> Explainer? {
        switch (category, area.id) {
        case (.spending, "SUBSCRIPTIONS"): with("subscriptions")
        case (.spending, "SHOPPING"): area.health == .strong ? nil : with("pay-later")
        case (.spending, _): area.health == .strong ? nil : with("budget")
        case (.saving, "EMERGENCY"): with("safety-net")
        case (.saving, "GOALS"): with("home")
        case (.saving, "PROTECTION"): with("protect")
        case (.investing, "amount"): with("funds")
        case (.investing, "stability"): with("spread")
        case (.investing, "rings"): with("compound")
        case (.investing, "cracks"): with("calm")
        default: nil
        }
    }

    /// The films that fit a customer's next steps, then the basics.
    static func picks(for workspace: Workspace) -> [Explainer] {
        var picks: [Explainer] = []
        for action in workspace.agentActions {
            if let film = before(action), !picks.contains(film) { picks.append(film) }
        }
        for id in ["funds", "pay-later", "safety-net"] {
            if let film = with(id), !picks.contains(film) { picks.append(film) }
        }
        return Array(picks.prefix(5))
    }
}

/// The cover of a film: its drawing on a tint of blue, a play button and the length.
struct ExplainerCover: View {
    let explainer: Explainer
    var compact = false

    private var tint: [Color] {
        switch explainer.category {
        case .spending: [Color(hex: 0xD9E2FB), Color(hex: 0xEEF2FD)]
        case .saving: [Color(hex: 0xD3E3F9), Color(hex: 0xECF4FD)]
        case .investing: [Color(hex: 0xDCDCFA), Color(hex: 0xF0EFFD)]
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: tint, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(Color.white.opacity(0.55))
                .scaleEffect(1.25)
                .offset(x: compact ? 14 : 50, y: compact ? 10 : 30)
            Image(explainer.art)
                .resizable()
                .scaledToFit()
                .padding(compact ? 9 : 20)
                .offset(x: compact ? 0 : 26)
            if !compact {
                HStack(alignment: .bottom) {
                    PlayButton(size: 38)
                    Spacer()
                    Text(explainer.length)
                        .appFont(12, .semibold, relativeTo: .caption1)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.brand.opacity(0.82), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .padding(10)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                PlayButton(size: 26)
            }
        }
        .aspectRatio(compact ? 1.3 : 1.6, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct PlayButton: View {
    var size: CGFloat = 38

    var body: some View {
        Circle()
            .fill(Color.brand)
            .frame(width: size, height: size)
            .overlay {
                Path { path in
                    path.move(to: CGPoint(x: size * 0.4, y: size * 0.31))
                    path.addLine(to: CGPoint(x: size * 0.4, y: size * 0.69))
                    path.addLine(to: CGPoint(x: size * 0.7, y: size * 0.5))
                    path.closeSubpath()
                }
                .fill(Color.white)
            }
            .shadow(color: Color.brand.opacity(0.3), radius: 6, y: 3)
    }
}

/// A film in a row of films: the cover, the title and the topic.
struct ExplainerCard: View {
    let explainer: Explainer
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            VStack(alignment: .leading, spacing: 8) {
                ExplainerCover(explainer: explainer)
                Text(explainer.title)
                    .appFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(Color.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .topLeading)
                Text("\(explainer.category.title), \(explainer.length) min")
                    .appFont(13, relativeTo: .footnote)
                    .foregroundStyle(Color.textMuted)
            }
            .frame(width: 216)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { ExplainerSheet(explainer: explainer) }
    }
}

/// A film beside the thing it explains: a small cover and the title, on one line.
struct ExplainerRow: View {
    let explainer: Explainer
    var lead = "Watch first"
    @State private var open = false

    var body: some View {
        Button { open = true } label: {
            HStack(spacing: 12) {
                ExplainerCover(explainer: explainer, compact: true)
                    .frame(width: 84)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(lead), \(explainer.length) min")
                        .appFont(13, relativeTo: .footnote)
                        .foregroundStyle(Color.textMuted)
                    Text(explainer.title)
                        .appFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(Color.ink)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Chevron()
            }
            .tile(padding: EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 12))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $open) { ExplainerSheet(explainer: explainer) }
    }
}

/// A row of films under a heading, to swipe through.
struct ExplainerShelf: View {
    let title: LocalizedStringKey
    let explainers: [Explainer]

    var body: some View {
        if !explainers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(explainers) { ExplainerCard(explainer: $0) }
                    }
                    .padding(.horizontal, Spacing.screenSide)
                }
                .padding(.horizontal, -Spacing.screenSide)
            }
        }
    }
}

/// What a film covers. The film itself is not part of the prototype, and the sheet says so.
struct ExplainerSheet: View {
    let explainer: Explainer

    var body: some View {
        FittedSheet {
            VStack(alignment: .leading, spacing: 18) {
                ExplainerCover(explainer: explainer)
                VStack(alignment: .leading, spacing: 6) {
                    Text(explainer.title)
                        .font(.display(24))
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(explainer.category.title), \(explainer.length) min")
                        .appFont(14, relativeTo: .subheadline)
                        .foregroundStyle(Color.textMuted)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(explainer.points.enumerated()), id: \.offset) { index, point in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .appFont(13, .semibold, relativeTo: .footnote)
                                .foregroundStyle(Color.accent)
                                .frame(width: 24, height: 24)
                                .background(Color.brandTint, in: Circle())
                            Text(point)
                                .appFont(16, lineHeight: 1.4)
                                .foregroundStyle(Color.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 12)
                        if index < explainer.points.count - 1 { Hairline() }
                    }
                }
                .tile(padding: EdgeInsets(top: 4, leading: 14, bottom: 4, trailing: 14))
                Text("This is what the film covers. In this prototype the film itself is not recorded yet.")
                    .appFont(13, relativeTo: .footnote)
                    .foregroundStyle(Color.textMuted)
            }
            .padding(.horizontal, Spacing.pageSide)
            .padding(.top, 28)
            .padding(.bottom, 20)
        }
    }
}
