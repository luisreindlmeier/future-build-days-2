import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit

/// What a terminal hands to the phone: which customer checked in.
struct TerminalHandoff: Equatable {
    let user: String

    var url: String { "dbkairos://checkup?user=\(user)" }

    init(user: String) {
        self.user = user
    }

    init?(url: String) {
        guard let components = URLComponents(string: url), components.scheme == "dbkairos",
              let user = components.queryItems?.first(where: { $0.name == "user" })?.value, !user.isEmpty else { return nil }
        self.init(user: user)
    }
}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 14, y: 14)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: image)
    }
}

/// The check-up at a self-service terminal in a branch. The big screen shows the tree, the score and the rings,
/// never an amount; the figures open on the client's own phone.
struct TerminalView: View {
    enum Step: Int { case attract, customer, consent, scan, result, handoff, advisor }

    @Environment(AppModel.self) private var model
    @State private var step: Step = TerminalView.firstStep
    @State private var taps = 0

    private static var firstStep: Step {
        switch DebugLaunch.screen {
        case "terminal-customer": .customer
        case "terminal-consent": .consent
        case "terminal-scan": .scan
        case "terminal-result": .result
        case "terminal-handoff": .handoff
        case "terminal-advisor": .advisor
        default: .attract
        }
    }

    /// A terminal is read from a step away, so everything on it is drawn larger than on a tablet in the hand.
    private static let zoom = 1.28

    var body: some View {
        GeometryReader { proxy in
            page
                .frame(width: proxy.size.width / Self.zoom, height: proxy.size.height / Self.zoom)
                .scaleEffect(Self.zoom)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .screenBackground()
        .sensoryFeedback(.soft, trigger: taps)
    }

    private var page: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Mascot(mood: .smile, size: 40, motion: .still)
                Text("Kairos")
                    .appFont(24, .bold)
                    .foregroundStyle(Color.ink)
                Spacer()
                if step != .attract {
                    Button("Start over") { go(.attract) }
                        .buttonStyle(.text)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            ZStack {
                switch step {
                case .attract: attract
                case .customer: CustomerPicker(title: "Who is checking in?", button: "Continue", large: true) { go(.consent) }
                case .consent: ConsentView(button: "Check my finances", large: true) { go(.scan) }
                case .scan: ScanView(steps: model.workspace?.scanSteps ?? [], large: true) { go(.result) }
                case .result: result
                case .handoff: handoff
                case .advisor: advisor
                }
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func go(_ next: Step) {
        taps += 1
        withAnimation(.easeInOut(duration: 0.4)) { step = next }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.display(44))
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .appFont(20, lineHeight: 1.4)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var attract: some View {
        VStack(spacing: 0) {
            Spacer()
            Mascot(mood: .smile, size: 260, enters: 0.2)
            title("How is your money doing?").padding(.top, 36)
            note("A check-up in two minutes. Free for clients.").padding(.top, 12)
            Spacer()
            Button("Start my check-up") { go(.customer) }
                .buttonStyle(PrimaryButtonStyle(height: 72, radius: 16, fontSize: 22))
            Text("Your figures appear on your phone, never on this screen.")
                .appFont(16)
                .foregroundStyle(Color.textMuted)
                .padding(.top, 16)
                .padding(.bottom, 36)
        }
        .transition(.opacity)
    }

    private var result: some View {
        VStack(spacing: 0) {
            if let workspace = model.workspace {
                TreeCanvas(tree: workspace.tree, interactive: false)
                    .aspectRatio(0.8, contentMode: .fit)
                    .background(LinearGradient(colors: [Color(hex: 0xC9D8FA), Color(hex: 0xEEF3FE)], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .frame(maxHeight: 410)
                    .padding(.top, 8)
                HStack(spacing: 22) {
                    ScoreRing(score: workspace.tree.overallHealth, size: 116, lineWidth: 11, caption: "Health")
                    ForEach(CategoryID.allCases) { category in
                        VStack(spacing: 10) {
                            ScoreRing(score: workspace.score(category), size: 84, lineWidth: 8)
                            Text(category.title).appFont(18, .medium).foregroundStyle(Color.ink)
                        }
                    }
                }
                .padding(.top, 22)
                note("\(workspace.tree.headline). The details are for your eyes only.").padding(.top, 20)
            }
            Spacer(minLength: 16)
            Button("Take it with me") { go(.handoff) }
                .buttonStyle(PrimaryButtonStyle(height: 72, radius: 16, fontSize: 22))
            Button("Talk to an advisor now") { go(.advisor) }
                .buttonStyle(SecondaryButtonStyle(fontSize: 20))
                .padding(.top, 14)
                .padding(.bottom, 36)
        }
        .transition(.opacity)
    }

    private var handoff: some View {
        VStack(spacing: 0) {
            Spacer()
            if let code = QRCode.image(TerminalHandoff(user: model.userID).url) {
                Image(uiImage: code)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 300, height: 300)
                    .padding(22)
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .tileShadow()
                    .accessibilityLabel("Code for the Kairos app")
            }
            title("Scan with your phone").padding(.top, 32)
            note("Open Kairos, tap your initial and choose Continue from a terminal. Your tree, your findings and your plan open there.").padding(.top, 12)
            Spacer()
            Button("Done") { go(.attract) }
                .buttonStyle(SecondaryButtonStyle(fontSize: 20))
                .padding(.bottom, 36)
        }
        .transition(.opacity)
    }

    private var advisor: some View {
        VStack(spacing: 0) {
            Spacer()
            Mascot(mood: .wink, size: 200, enters: 0.2)
            title("An advisor is on the way").padding(.top, 32)
            note(model.workspace?.prediction.actions?.output?.advisorMeeting?.sentence ?? "They have a summary of your check-up, so you can start where we left off.").padding(.top, 12)
            Spacer()
            Button("Take it with me too") { go(.handoff) }
                .buttonStyle(PrimaryButtonStyle(height: 72, radius: 16, fontSize: 22))
                .padding(.bottom, 36)
        }
        .transition(.opacity)
    }
}

/// On the phone: picks up a check-up from a terminal by its code.
struct TerminalCodeView: View {
    @Environment(AppModel.self) private var model
    @State private var scanning = false
    @State private var handoff: TerminalHandoff?
    @State private var failed = false

    private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.sectionGap) {
                if handoff != nil, let workspace = model.workspace {
                    CoachLine(text: "There you are, \(workspace.tree.name). I picked up your check-up from the terminal. Your tree, your findings and your plan are all here.", mood: .cheer, size: 72)
                } else {
                    CoachLine(text: "Did a check-up at a terminal in a branch? Scan the code on its screen and it opens here.", mood: .curious, size: 72)
                    Button("Scan the code") { scanning = true }
                        .buttonStyle(.primary)
                        .disabled(!canScan)
                    if !canScan {
                        Text("The camera is not available here.")
                            .appFont(14, relativeTo: .subheadline)
                            .foregroundStyle(Color.textMuted)
                        Button("Use the demo code") { accept(TerminalHandoff(user: model.userID).url) }
                            .buttonStyle(.secondary)
                    }
                    if failed {
                        Text("That is not a Kairos code.")
                            .appFont(14, relativeTo: .subheadline)
                            .foregroundStyle(Color.ink)
                    }
                }
            }
            .padding(.horizontal, Spacing.screenSide)
            .padding(.top, 8)
        }
        .screenBackground()
        .navigationTitle("Terminal")
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $scanning) {
            CodeScanner { text in
                scanning = false
                accept(text)
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: handoff)
    }

    private func accept(_ text: String) {
        guard let parsed = TerminalHandoff(url: text) else { failed = true; return }
        failed = false
        handoff = parsed
        Task { await model.select(parsed.user) }
    }
}

/// The camera, reading QR codes.
struct CodeScanner: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onFound: (String) -> Void
        private var done = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case let .barcode(code) = item, let text = code.payloadStringValue {
                    done = true
                    dataScanner.stopScanning()
                    onFound(text)
                    return
                }
            }
        }
    }
}
