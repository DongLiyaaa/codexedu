import Foundation
import Darwin
import QuotaCore

struct LoginSession: Codable {
    let credentials: Credentials
    let refreshToken: String?
}

enum LoginError: LocalizedError {
    case failed(String)
    var errorDescription: String? { if case .failed(let text) = self { return text }; return nil }
}

// Credentials belong only to this application; never read another client's auth file.
enum CredentialStore {
    private static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexIsland", isDirectory: true)
    private static var file: URL { directory.appendingPathComponent("session.json") }
    private static func prepare() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try fm.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw LoginError.failed("凭据目录类型或所有者异常，已停止访问。")
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    private static func validateFile() throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw LoginError.failed("凭据文件类型或所有者异常，已停止访问。")
        }
    }
    static func load() throws -> LoginSession? {
        try prepare()
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        try validateFile()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        do {
            let value = try JSONDecoder().decode(LoginSession.self, from: Data(contentsOf: file))
            guard !value.credentials.accessToken.isEmpty, !value.credentials.accountId.isEmpty else {
                throw LoginError.failed("登录文件无效，请重新授权。")
            }
            return value
        } catch { throw LoginError.failed("登录文件无效，请重新授权。") }
    }
    static func save(_ value: LoginSession) throws {
        try prepare()
        if FileManager.default.fileExists(atPath: file.path) { try validateFile() }
        let temporary = directory.appendingPathComponent(".session-" + UUID().uuidString)
        let data = try JSONEncoder().encode(value)
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw LoginError.failed("无法保存本应用登录文件。")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard rename(temporary.path, file.path) == 0 else {
            throw LoginError.failed("更新登录文件失败，请检查目录权限。")
        }
    }
    static func remove() throws {
        try prepare()
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try validateFile()
        try FileManager.default.removeItem(at: file)
    }
}

// Public Codex device flow; no browser cookies and no existing Codex auth files.
final class DeviceAuthorization: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    struct Code {
        let id: String
        let userCode: String
        let interval: Double
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    private func post(_ path: String, body: [String: String]) async throws -> (Int, [String: Any]) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://auth.openai.com" + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw LoginError.failed("授权服务响应异常。") }
        return (status, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
    }
    func start() async throws -> Code {
        let (status, body) = try await post("/api/accounts/deviceauth/usercode", body: ["client_id": clientID])
        guard status == 200, let id = body["device_auth_id"] as? String,
              let code = (body["user_code"] ?? body["usercode"]) as? String else {
            throw LoginError.failed("无法发起设备授权（HTTP \(status)）。请确认账号支持设备登录。")
        }
        let interval = (body["interval"] as? Double) ?? Double(body["interval"] as? String ?? "5") ?? 5
        return Code(id: id, userCode: code, interval: max(5, min(interval, 60)))
    }
    func complete(_ code: Code) async throws -> LoginSession {
        let deadline = Date().addingTimeInterval(900)
        while Date() < deadline {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(code.interval))
            let (status, body) = try await post("/api/accounts/deviceauth/token", body: ["device_auth_id": code.id, "user_code": code.userCode])
            if status == 403 || status == 404 { continue }
            guard status == 200, let authorization = body["authorization_code"] as? String,
                  let verifier = body["code_verifier"] as? String else { throw LoginError.failed("授权未完成（HTTP \(status)），请重新登录。") }
            let (tokenStatus, tokens) = try await post("/oauth/token", body: ["grant_type": "authorization_code", "client_id": clientID, "code": authorization, "code_verifier": verifier, "redirect_uri": "https://auth.openai.com/deviceauth/callback"])
            guard tokenStatus == 200 else { throw LoginError.failed("授权令牌交换失败（HTTP \(tokenStatus)）。") }
            return try parse(tokens)
        }
        throw LoginError.failed("授权已超时，请重新点击登录。")
    }
    func refresh(_ value: LoginSession) async throws -> LoginSession {
        guard let refresh = value.refreshToken else { throw LoginError.failed("登录已过期，请重新授权。") }
        let (status, body) = try await post("/oauth/token", body: ["grant_type": "refresh_token", "client_id": clientID, "refresh_token": refresh])
        guard status == 200 else { throw LoginError.failed("登录已过期，请重新授权。") }
        return try parse(body, previous: value)
    }
    private func parse(_ tokens: [String: Any], previous: LoginSession? = nil) throws -> LoginSession {
        guard let access = tokens["access_token"] as? String else { throw LoginError.failed("授权响应缺少令牌。") }
        let token = tokens["id_token"] as? String ?? access
        let pieces = token.split(separator: ".")
        var account: String?
        if pieces.count == 3 {
            var base = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            base += String(repeating: "=", count: (4 - base.count % 4) % 4)
            if let data = Data(base64Encoded: base), let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                account = (claims["https://api.openai.com/auth"] as? [String: Any])?["chatgpt_account_id"] as? String
            }
        }
        guard let accountID = account ?? previous?.credentials.accountId else { throw LoginError.failed("授权未返回 Codex 账号标识。") }
        return LoginSession(credentials: Credentials(accessToken: access, accountId: accountID), refreshToken: tokens["refresh_token"] as? String ?? previous?.refreshToken)
    }
}
