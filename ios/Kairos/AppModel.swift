import Foundation
import Observation

enum DataOrigin: Sendable { case live, snapshot }

/// The month before and the month after, for the review that follows "advance a month".
struct MonthReview: Sendable {
    let before: Workspace
    let after: Workspace
}

/// The app's state: which customer, their workspace from the backend, and what was just done to it.
@Observable
final class AppModel {
    private(set) var users: [UserSummary] = Snapshot.users()
    private(set) var workspace: Workspace?
    private(set) var origin: DataOrigin = .snapshot
    private(set) var busy = false
    private(set) var storm: StormResult?
    var review: MonthReview?
    var notice: String?

    var onboardingDone: Bool { didSet { store.set(onboardingDone, forKey: Key.onboardingDone) } }
    private(set) var userID: String { didSet { store.set(userID, forKey: Key.userID) } }
    var baseURL: String { didSet { store.set(baseURL, forKey: Key.baseURL) } }

    private let store: UserDefaults

    private enum Key {
        static let onboardingDone = "onboardingDone", userID = "userID", baseURL = "baseURL"
    }

    init(store: UserDefaults = .standard) {
        self.store = store
        onboardingDone = store.bool(forKey: Key.onboardingDone)
        userID = store.string(forKey: Key.userID) ?? "maya"
        baseURL = store.string(forKey: Key.baseURL) ?? KairosAPI.defaultBase
        workspace = Snapshot.workspace(userID)
    }

    var user: UserSummary? { users.first { $0.id == userID } }
    var isLive: Bool { origin == .live }
    private var api: KairosAPI? { KairosAPI(base: baseURL) }

    /// Reads the customer's workspace from the backend; without a backend the saved copy stays.
    func refresh() async {
        guard let api else { return useSnapshot() }
        do {
            async let list = api.users()
            async let fresh = api.workspace(userID)
            users = try await list
            workspace = try await fresh
            origin = .live
        } catch {
            useSnapshot()
        }
    }

    func select(_ id: String) async {
        guard id != userID || workspace == nil else { return }
        userID = id
        storm = nil
        workspace = Snapshot.workspace(id) ?? workspace
        await refresh()
    }

    func commit(_ action: AgentAction) async {
        await command { api in try await api.commit(self.userID, action: action.actionID) }
    }

    func drop(_ tracked: TrackedAction) async {
        await command { api in try await api.drop(self.userID, action: tracked.actionId) }
    }

    /// One demo month on: the backend checks the commitments against the bookings and reads the tree again.
    func advanceMonth() async {
        guard let before = workspace else { return }
        await command { api in try await api.advanceMonth(self.userID) }
        if let after = workspace, isLive, after.progress.month != before.progress.month {
            review = MonthReview(before: before, after: after)
        }
    }

    func saveProject(name: String, type: String, target: Double, date: String) async {
        await command { api in try await api.saveProject(self.userID, name: name, type: type, target: target, saved: 0, date: date) }
    }

    func resetDemo() async {
        await command { api in try await api.resetDemo() }
    }

    func runStorm() async {
        storm = nil
        if isLive, let api, let result = try? await api.storm(userID) {
            storm = result
        } else {
            storm = Snapshot.storm(userID)
        }
    }

    func clearStorm() {
        storm = nil
    }

    func startOver() {
        store.removeObject(forKey: Key.onboardingDone)
        onboardingDone = false
    }

    private func command(_ work: (KairosAPI) async throws -> Void) async {
        guard isLive, let api else {
            notice = "This needs the backend. The app is showing a saved copy."
            return
        }
        busy = true
        defer { busy = false }
        do {
            try await work(api)
            workspace = try await api.workspace(userID)
        } catch {
            notice = "The backend did not answer. Nothing was changed."
        }
    }

    private func useSnapshot() {
        origin = .snapshot
        if workspace?.userId != userID { workspace = Snapshot.workspace(userID) }
        if users.isEmpty { users = Snapshot.users() }
    }
}
