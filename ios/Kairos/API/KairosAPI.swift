import Foundation

/// The team's backend (`backend/`, port 8080). The app reads one workspace per customer and sends the same
/// commands as the web dashboard: commit, drop, advance a month, storm, save a project.
struct KairosAPI: Sendable {
    static let defaultBase = "http://localhost:8080"

    let base: URL

    init?(base: String) {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespaces)), url.scheme != nil else { return nil }
        self.base = url
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 6
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func users() async throws -> [UserSummary] {
        try await send("api/users")
    }

    /// The workspace is ready once the agents have answered; until then the backend reports RUNNING.
    func workspace(_ id: String) async throws -> Workspace {
        var workspace: Workspace = try await send("api/users/\(id)/workspace")
        var tries = 0
        while workspace.prediction.status == "RUNNING", tries < 20 {
            try await Task.sleep(for: .milliseconds(700))
            workspace = try await send("api/users/\(id)/workspace")
            tries += 1
        }
        return workspace
    }

    func commit(_ id: String, action: String) async throws {
        try await command("api/users/\(id)/actions/\(action)/commit")
    }

    func drop(_ id: String, action: String) async throws {
        try await command("api/users/\(id)/actions/\(action)/drop")
    }

    func advanceMonth(_ id: String) async throws {
        try await command("api/users/\(id)/advance-month?months=1")
    }

    func storm(_ id: String) async throws -> StormResult {
        try await send("api/users/\(id)/storm", method: "POST")
    }

    func saveProject(_ id: String, name: String, type: String, target: Double, saved: Double, date: String) async throws {
        let body: [String: Any] = ["name": name, "type": type, "targetAmount": target, "savedAmount": saved, "targetDate": date]
        try await command("api/users/\(id)/projects", body: try JSONSerialization.data(withJSONObject: body))
    }

    func resetDemo() async throws {
        try await command("api/demo/reset")
    }

    private func request(_ path: String, method: String, body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: base) ?? base)
        request.httpMethod = method
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send<T: Decodable>(_ path: String, method: String = "GET") async throws -> T {
        let (data, response) = try await Self.session.data(for: request(path, method: method))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func command(_ path: String, body: Data? = nil) async throws {
        let (_, response) = try await Self.session.data(for: request(path, method: "POST", body: body))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
    }
}

/// The copy of the backend's answers that ships with the app, so it opens without a backend.
enum Snapshot {
    static func users() -> [UserSummary] {
        load("users") ?? []
    }

    static func workspace(_ id: String) -> Workspace? {
        load("workspace-\(id)")
    }

    static func storm(_ id: String) -> StormResult? {
        load("storm-\(id)")
    }

    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
