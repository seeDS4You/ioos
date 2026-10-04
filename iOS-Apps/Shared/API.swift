import Foundation
import Security
import Combine
import LocalAuthentication

struct ServerError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
    var uncertain: Bool { status == 0 || status == 408 || status == 429 || status >= 500 }
}

enum SecureSession {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Bundle.main.bundleIdentifier ?? AppKind.name,
         kSecAttrAccount as String: "https://yourallsiss.co.uk/session"]
    }
    static func read() -> Data? {
        var values = query; values[kSecReturnData as String] = true; values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(values as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
    static func write(_ data: Data) throws {
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw ServerError(status: 0, message: "Unable to save your secure session.") }
        var values = query; values[kSecValueData as String] = data
        values[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(values as CFDictionary, nil) == errSecSuccess else { throw ServerError(status: 0, message: "Unable to save your secure session.") }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}

final class SameOriginDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "yourallsiss.co.uk" ? request : nil)
    }
}

@MainActor final class API: ObservableObject {
    static let shared = API()
    static let base = URL(string: "https://yourallsiss.co.uk")!
    @Published var user: Row?
    @Published var message: String?
    @Published var restoring = false
    private var cookies: [HTTPCookie] = []
    private let session: URLSession
    var serverOffset: TimeInterval = 0
    var now: Date { Date().addingTimeInterval(serverOffset) }
    var hasSession: Bool { !cookies.isEmpty }

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config, delegate: SameOriginDelegate(), delegateQueue: nil)
        if let data = SecureSession.read(), let stored = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            cookies = stored.compactMap { item in
                guard let name = item["name"] as? String, let value = item["value"] as? String,
                      let domain = item["domain"] as? String, domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == Self.base.host else { return nil }
                var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: item["path"] as? String ?? "/", .secure: "TRUE"]
                if let expiry = item["expiry"] as? Double { properties[.expires] = Date(timeIntervalSince1970: expiry) }
                return HTTPCookie(properties: properties)
            }.filter { $0.expiresDate.map { $0 > Date() } ?? true }
        }
    }

    func data(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard path.hasPrefix("/api/"), let url = URL(string: path, relativeTo: Self.base)?.absoluteURL,
              url.host == Self.base.host else { throw ServerError(status: 0, message: "Invalid API address.") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        cookies.removeAll { $0.expiresDate.map { $0 <= Date() } ?? false }
        let matching = cookies.filter { url.path.hasPrefix($0.path) }
        for (key, value) in HTTPCookie.requestHeaderFields(with: matching) { request.setValue(value, forHTTPHeaderField: key) }
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw ServerError(status: 0, message: error.localizedDescription) }
        guard let http = response as? HTTPURLResponse else { throw ServerError(status: 0, message: "Invalid server response.") }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields { headers[String(describing: key)] = String(describing: value) }
        let new = HTTPCookie.cookies(withResponseHeaderFields: headers, for: Self.base)
        for cookie in new where cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: ".")) == Self.base.host {
            cookies.removeAll { $0.name == cookie.name && $0.path == cookie.path }
            if cookie.expiresDate.map({ $0 > Date() }) ?? true { cookies.append(cookie) }
        }
        if !new.isEmpty { try persist() }
        if http.statusCode == 401 { user = nil; clear() }
        guard (200..<300).contains(http.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            let details = (object["details"] as? [[String: Any]] ?? []).compactMap { $0["msg"] as? String }.joined(separator: "\n")
            let text = object["error"] as? String ?? object["message"] as? String ?? "Request failed (\(http.statusCode))."
            throw ServerError(status: http.statusCode, message: details.isEmpty ? text : "\(text)\n\(details)")
        }
        return data
    }
    func call(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Row {
        let bytes = try await data(path, method: method, body: body)
        guard !bytes.isEmpty else { return Row() }
        guard let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw ServerError(status: 0, message: "Unexpected server response.") }
        let row = Row(object)
        if let error = object["error"] as? String { throw ServerError(status: 400, message: error) }
        if let success = object["success"] as? Bool, !success { throw ServerError(status: 400, message: row.text("message", fallback: "Request failed.")) }
        if let timestamp = UKTime.parse(row.text("server_time")) { serverOffset = timestamp.timeIntervalSinceNow }
        return row
    }
    private func persist() throws {
        let stored = cookies.map { cookie -> [String: Any] in
            var item: [String: Any] = ["name": cookie.name, "value": cookie.value, "domain": cookie.domain, "path": cookie.path]
            if let expiry = cookie.expiresDate { item["expiry"] = expiry.timeIntervalSince1970 }
            return item
        }
        try SecureSession.write(JSONSerialization.data(withJSONObject: stored))
    }
    private func accepted(_ candidate: Row) -> Bool {
        candidate.id > 0 && (AppKind.role != "admin" || ["admin", "moderator"].contains(candidate.text("role")))
    }
    func login(_ email: String, _ password: String) async throws {
        let path = AppKind.supervisor ? "/api/supervisor/login" : "/api/auth/login"
        let response = try await call(path, method: "POST", body: ["email": email.trimmingCharacters(in: .whitespacesAndNewlines), "password": password])
        let candidate = response.object("user")
        guard accepted(candidate) else { await logout(); throw ServerError(status: 403, message: "This account cannot access \(AppKind.name).") }
        user = candidate
    }
    func restore() async {
        guard hasSession else { return }
        restoring = true; defer { restoring = false }
        do {
            if AppKind.role == "staff" {
                let context = LAContext(); var error: NSError?
                if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
                    guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your SISS Staff session") else { return }
                }
            }
            let response = try await call(AppKind.supervisor ? "/api/supervisor/me" : "/api/auth/me")
            let candidate = response.object("user")
            guard accepted(candidate) else { await logout(); return }
            user = candidate
        } catch { message = error.localizedDescription }
    }
    func clear() { cookies.removeAll(); SecureSession.clear() }
    func logout() async {
        _ = try? await call("/api/auth/logout", method: "POST")
        clear(); user = nil
    }
}
