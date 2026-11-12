import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let fromCoach: Bool
    var text: String
    var links: [CoachReply.Link] = []
    var mood: Mood = .smile
}

/// The conversation with the coach. Every answer is one of the backend's own texts for this customer: the
/// agents wrote them and their guardrails checked every figure, so the app adds no model of its own on top.
@Observable
final class CoachSession {
    var messages: [ChatMessage] = []
    var thinking = false

    func ask(_ question: String, workspace: Workspace) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !thinking else { return }
        messages.append(ChatMessage(fromCoach: false, text: trimmed))
        thinking = true
        let reply = CoachAnswers.reply(to: trimmed, in: workspace)
        try? await Task.sleep(for: .milliseconds(500))
        messages.append(ChatMessage(fromCoach: true, text: reply.text, links: reply.links, mood: reply.mood))
        thinking = false
    }
}

struct CoachView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @State private var session = CoachSession()
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("AI coach. Its figures come from the simulation and are checked before you see them. Product advice comes from your advisor.")
                        .appFont(13, relativeTo: .footnote)
                        .foregroundStyle(Color.textMuted)
                    if let workspace = model.workspace {
                        CoachBubble(message: ChatMessage(fromCoach: true, text: CoachAnswers.greeting(workspace), mood: .smile)) { _ in }
                    }
                    ForEach(session.messages.filter { !$0.text.isEmpty }) { message in
                        if message.fromCoach {
                            CoachBubble(message: message, open: open)
                        } else {
                            Text(message.text)
                                .appFont(16)
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.leading, 48)
                        }
                    }
                    if session.thinking {
                        HStack(spacing: 12) {
                            Mascot(mood: .curious, size: 40, motion: .looking)
                            ProgressView().controlSize(.small)
                        }
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, Spacing.screenSide)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.messages.count) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: session.thinking) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .screenBackground()
        .navigationTitle("Coach")
        .toolbarTitleDisplayMode(.large)
        .sensoryFeedback(.soft, trigger: session.messages.count)
        .onChange(of: model.userID) { session.messages = [] }
        .task {
            if let question = DebugLaunch.value("-ask") { send(question.replacingOccurrences(of: "_", with: " ")) }
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if !session.thinking {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CoachAnswers.suggestions.filter { suggestion in !session.messages.contains { $0.text == suggestion } }, id: \.self) { suggestion in
                            Button(suggestion) { send(suggestion) }
                                .buttonStyle(.secondarySmall)
                        }
                    }
                    .padding(.horizontal, Spacing.screenSide)
                    .padding(.vertical, 6)
                }
            }
            HStack(spacing: 10) {
                TextField("Ask about your money", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .appFont(16)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(.recessed(Color.well), in: RoundedRectangle(cornerRadius: Radius.input + 6, style: .continuous))
                Button { send(draft) } label: {
                    Icon("arrow-up", size: 18)
                        .environment(\.inkColor, .white)
                        .frame(width: 36, height: 36)
                        .background(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.divider : Color.accent, in: Circle())
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || session.thinking)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, Spacing.screenSide)
            .padding(.bottom, 8)
        }
        .background(Color.appBackground)
    }

    private func send(_ text: String) {
        guard let workspace = model.workspace else { return }
        draft = ""
        Task { await session.ask(text, workspace: workspace) }
    }

    private func open(_ link: CoachReply.Link) {
        switch link {
        case let .action(id):
            router.action = model.workspace?.agentActions.first { $0.actionID == id }
        case let .category(id):
            router.tab = .home
            router.homePath = [.category(id)]
        case .prediction:
            router.tab = .home
            router.homePath = [.prediction]
        case .tree:
            router.tab = .tree
        case .advisor:
            router.openAdvisor()
        }
    }
}

struct CoachBubble: View {
    let message: ChatMessage
    let open: (CoachReply.Link) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Mascot(mood: message.mood, size: 40, motion: .still, enters: 0)
            VStack(alignment: .leading, spacing: 10) {
                Text(message.text)
                    .appFont(16, lineHeight: 1.42)
                    .foregroundStyle(Color.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(message.links.enumerated()), id: \.offset) { _, link in
                    Button { open(link) } label: {
                        HStack(spacing: 6) {
                            Text(title(link))
                            Icon("arrow-right", size: 15)
                        }
                    }
                    .buttonStyle(.secondarySmall)
                }
            }
            .padding(.top, 2)
        }
    }

    private func title(_ link: CoachReply.Link) -> String {
        switch link {
        case .action: "Show me the step"
        case let .category(id): id.title
        case .prediction: "Your outlook"
        case .tree: "Your wealth tree"
        case .advisor: "Summary for my advisor"
        }
    }
}
