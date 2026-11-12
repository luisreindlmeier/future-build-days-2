import SwiftUI

/// The second tab: the wealth tree to turn, with every part to tap, and the storm test.
struct TreeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selected: TreePart?
    @State private var lean = 0.0
    @State private var storming = false

    var body: some View {
        ScrollView {
            if let tree = model.workspace?.tree {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(tree.headline)
                            .appFont(20, .semibold, relativeTo: .title3)
                            .foregroundStyle(Color.ink)
                        HStack(spacing: 8) {
                            HealthChip(health: Health(status: tree.status), text: tree.status.replacingOccurrences(of: "_", with: " ").capitalized(with: nil).sentenceCased)
                            HStack(spacing: 5) {
                                Icon(Self.weatherIcon(tree.weather.type), size: 16)
                                Text(tree.weather.type.capitalized).appFont(13, .medium, relativeTo: .footnote).foregroundStyle(Color.ink)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        if tree.weather.type != "CALM" {
                            Text(tree.weather.reason).appFont(14, relativeTo: .subheadline).foregroundStyle(Color.textMuted)
                        }
                    }
                    .padding(.top, 8)
                    treeBlock(tree)
                    chips(tree)
                    detail(tree)
                    stormBlock
                }
                .padding(.horizontal, Spacing.screenSide)
                .padding(.bottom, 32)
            }
        }
        .screenBackground()
        .navigationTitle("Your wealth tree")
        .toolbarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.firm, trigger: storming) { _, now in now }
        .onChange(of: model.userID) { selected = nil; lean = 0; model.clearStorm() }
        .task {
            // For checks: `-part trunk`, `-part soil`, `-part leaf:EATING_OUT`, `-part root:EMERGENCY`, `-part storm`.
            guard let name = DebugLaunch.value("-part"), let tree = model.workspace?.tree else { return }
            let pieces = name.split(separator: ":").map(String.init)
            switch pieces[0] {
            case "storm": runStorm()
            case "trunk": selected = .trunk
            case "soil": selected = .soil
            case "leaf": selected = pieces.count > 1 ? .leaf(pieces[1]) : tree.leaves.first.map { .leaf($0.id) }
            case "root": selected = pieces.count > 1 ? .root(pieces[1]) : tree.roots.first.map { .root($0.id) }
            case "branch": selected = tree.branches.first.map { .branch($0.id) }
            default: break
            }
        }
    }

    private var stormy: Bool { storming || model.storm != nil }

    private func treeBlock(_ tree: TreeState) -> some View {
        TreeCanvas(tree: tree, selected: $selected, lean: lean, weather: stormy ? "STORM" : nil)
            .aspectRatio(0.8, contentMode: .fit)
            .background {
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xC9D8FA), Color(hex: 0xEEF3FE)], startPoint: .top, endPoint: .bottom)
                    RadialGradient(colors: [Color.white.opacity(0.85), Color.white.opacity(0)], center: UnitPoint(x: 0.12, y: 0.06), startRadius: 0, endRadius: 190)
                    LinearGradient(colors: [Color(hex: 0x66709A), Color(hex: 0xC9D0E4)], startPoint: .top, endPoint: .bottom)
                        .opacity(stormy ? 1 : 0)
                }
            }
            .overlay {
                if stormy { Rain().transition(.opacity) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .animation(.easeInOut(duration: 0.5), value: stormy)
    }

    /// Every part by name, for those who would rather not aim at a leaf.
    private func chips(_ tree: TreeState) -> some View {
        let parts: [(part: TreePart, icon: String, title: String)] =
            tree.leaves.prefix(8).map { (.leaf($0.id), Workspace.leafIcon($0.category), $0.label) }
            + [(.trunk, "trending-up", "Trunk")]
            + tree.roots.prefix(4).map { (.root($0.id), Workspace.rootIcon($0.category), $0.label) }
            + tree.branches.prefix(2).map { (.branch($0.id), "target", $0.name) }
            + [(.soil, "graduation-cap", "Soil")]
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(parts, id: \.part) { item in
                        let chosen = selected == item.part
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { selected = chosen ? nil : item.part }
                        } label: {
                            HStack(spacing: 6) {
                                Icon(item.icon, size: 16)
                                Text(item.title).appFont(14, .medium, relativeTo: .subheadline)
                            }
                            .environment(\.inkColor, chosen ? .white : .ink)
                            .foregroundStyle(chosen ? Color.white : Color.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(chosen ? Color.brand : Color.surface)
                                    .keyShadow()
                            }
                        }
                        .buttonStyle(.plain)
                        .id(item.part)
                    }
                }
                .padding(.horizontal, Spacing.screenSide)
                .padding(.vertical, 6)
            }
            .padding(.horizontal, -Spacing.screenSide)
            .onChange(of: selected) {
                if let selected { withAnimation { proxy.scrollTo(selected, anchor: .center) } }
            }
        }
    }

    /// What the colours of the leaves say.
    private var key: some View {
        HStack(spacing: 14) {
            ForEach([(Color(hex: 0x3CA552), "In line"), (Color(hex: 0xD6A626), "Above peers"), (Color(hex: 0xB7572B), "Far above")], id: \.1) { color, word in
                HStack(spacing: 6) {
                    Circle().fill(color).frame(width: 9, height: 9)
                    Text(word).appFont(13, relativeTo: .footnote).foregroundStyle(Color.textMuted)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func detail(_ tree: TreeState) -> some View {
        switch selected {
        case let .leaf(id):
            if let leaf = tree.leaves.first(where: { $0.id == id }) {
                part(icon: "leaf", title: "\(leaf.label), a bough of leaves", health: Health(status: leaf.health), word: leaf.health == "HEALTHY" ? "In line" : leaf.health == "WILTING" ? "Above peers" : "Far above peers", text: leaf.detail)
            }
        case let .root(id):
            if let root = tree.roots.first(where: { $0.id == id }) {
                part(icon: "piggy-bank", title: root.label, health: Health(status: root.status), word: nil, text: root.detail)
            }
        case let .branch(id):
            if let branch = tree.branches.first(where: { $0.id == id }) {
                part(icon: "target", title: "\(branch.name), a project", health: branch.fruit == true ? .strong : .growing, word: branch.fruit == true ? "Funded" : branch.blossom == true ? "In blossom" : "Growing", text: branch.detail)
            }
        case .trunk:
            part(icon: "trending-up", title: "The trunk, your investments", health: Health(status: tree.trunk.status), word: nil,
                 text: tree.trunk.detail + " " + Format.count(tree.trunk.rings, "ring") + " for years of regular investing, " + (tree.trunk.cracks == 0 ? "no cracks." : Format.count(tree.trunk.cracks, "crack") + " to look at."))
        case .soil:
            part(icon: "graduation-cap", title: "The soil, your confidence with money", health: Health(status: tree.soil.status), word: nil, text: tree.soil.detail)
        case nil:
            VStack(alignment: .leading, spacing: 0) {
                key.padding(.vertical, 12)
                Hairline()
                legend("leaf", "Leaves", "what you spend, one bough per category")
                Hairline()
                legend("trending-up", "Trunk", "what you invest")
                Hairline()
                legend("piggy-bank", "Roots", "what you have set aside")
                Hairline()
                legend("graduation-cap", "Soil", "your confidence with money")
                Hairline()
                legend("target", "Side branches", "your projects")
            }
            .tile(padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    private func part(icon: String, title: String, health: Health, word: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Icon(icon, size: 20)
                Text(title).appFont(17, .semibold).foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                HealthChip(health: health, text: word, compact: true)
            }
            Text(text)
                .appFont(15, relativeTo: .subheadline, lineHeight: 1.4)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tile()
        .transition(.opacity)
    }

    private func legend(_ icon: String, _ title: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Icon(icon, size: 18)
            Text(title).appFont(15, .medium, relativeTo: .subheadline).foregroundStyle(Color.ink)
            Text(text).appFont(14, relativeTo: .subheadline).foregroundStyle(Color.textMuted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
    }

    @ViewBuilder private var stormBlock: some View {
        if let storm = model.storm {
            VStack(alignment: .leading, spacing: 12) {
                CoachLine(text: storm.message, mood: storm.recovers ? .happy : .curious, size: 52)
                Button("Calm again") {
                    withAnimation(.spring(duration: 0.6)) { lean = 0 }
                    model.clearStorm()
                }
                .buttonStyle(.secondary)
            }
            .tile()
        } else {
            Button(storming ? "The storm is passing" : "Run the storm test") { runStorm() }
                .buttonStyle(.secondary)
                .disabled(storming)
        }
    }

    private func runStorm() {
        storming = true
        Task {
            await model.runStorm()
            guard let storm = model.storm else { storming = false; return }
            if reduceMotion {
                lean = storm.recovers ? 0 : storm.leanDegrees / 3
            } else {
                withAnimation(.easeInOut(duration: 0.45)) { lean = storm.leanDegrees }
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation(.easeInOut(duration: 0.4)) { lean = -storm.leanDegrees * 0.4 }
                try? await Task.sleep(for: .milliseconds(450))
                withAnimation(.spring(duration: 0.8, bounce: 0.3)) { lean = storm.recovers ? 0 : storm.leanDegrees / 3 }
            }
            storming = false
        }
    }

    static func weatherIcon(_ type: String) -> String {
        switch type {
        case "BREEZY": "cloud"
        case "WINDY": "wind"
        case "STORM": "cloud-lightning"
        default: "sun"
        }
    }
}

/// Rain over the tree while the storm test runs.
private struct Rain: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                var drops = Path()
                for drop in 0..<70 {
                    let seed = Double(drop) * 0.6180339887
                    let column = seed.truncatingRemainder(dividingBy: 1)
                    let fall = (time * (0.9 + 0.5 * column) + seed * 3.7).truncatingRemainder(dividingBy: 1)
                    let x = column * (size.width + 80) - fall * 60, y = fall * (size.height + 40) - 20
                    drops.move(to: CGPoint(x: x, y: y))
                    drops.addLine(to: CGPoint(x: x - 7, y: y + 18))
                }
                context.stroke(drops, with: .color(Color.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension String {
    /// "Needs Care" as "Needs care".
    var sentenceCased: String { prefix(1).uppercased() + dropFirst().lowercased() }
}
