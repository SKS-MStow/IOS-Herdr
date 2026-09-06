import Foundation

final class ControllerClient {
    let connection: Connection
    private let session: URLSession
    init(connection: Connection, session: URLSession = .shared) { self.connection = connection; self.session = session }
    static func validatedURL(_ value: String) throws -> URL {
        guard var parts = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw APIError(message: "Enter the HTTPS controller address, including its port.", code: "invalid_url") }
        parts.path = ""; guard let url = parts.url else { throw APIError(message: "Invalid controller address.", code: "invalid_url") }; return url
    }
    func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        let base = try Self.validatedURL(connection.serverURL)
        guard let url = URL(string: base.absoluteString + path) else { throw APIError(message: "Invalid request address.", code: "invalid_url") }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = method == "GET" ? 25 : 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !connection.token.isEmpty { request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw APIError(message: "No response from the controller.", code: "connection") }
        guard (200..<300).contains(response.statusCode) else {
            let error = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw APIError(message: error?.error.message ?? "The controller returned an error (\(response.statusCode)).", code: error?.error.code ?? "http_error")
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(T.self, from: data)
    }
    static func agentPath(_ id: String) -> String {
        id.addingPercentEncoding(withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? ""
    }
}
