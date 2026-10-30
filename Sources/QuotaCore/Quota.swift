import Foundation

public struct QuotaWindow: Decodable, Equatable {
    public let usedPercent: Double
    public let limitWindowSeconds: Int?
    public let resetAt: Double?
    public var remaining: Double { max(0, min(100, 100 - usedPercent)) }
    public var title: String {
        guard let seconds = limitWindowSeconds, seconds > 0 else { return "额度窗口" }
        if seconds % 604800 == 0 { return "\(seconds / 604800) 周额度" }
        if seconds % 86400 == 0 { return "\(seconds / 86400) 天额度" }
        if seconds % 3600 == 0 { return "\(seconds / 3600) 小时额度" }
        return "\(seconds / 60) 分钟额度"
    }
    public func resetDescription(now: Date) -> String {
        guard let resetAt else { return "重置时间未知" }
        let seconds = resetAt - now.timeIntervalSince1970
        guard seconds > 0 else { return "等待服务端确认重置" }
        let minutes = Int(ceil(seconds / 60))
        if minutes >= 1440 { return "\(minutes / 1440) 天 \(minutes % 1440 / 60) 小时后重置" }
        if minutes >= 60 { return "\(minutes / 60) 小时 \(minutes % 60) 分钟后重置" }
        return "\(minutes) 分钟后重置"
    }
}
public struct RateLimit: Decodable {
    public let primaryWindow: QuotaWindow?
    public let secondaryWindow: QuotaWindow?
    public let limitReached: Bool?
    public var windows: [QuotaWindow] { [primaryWindow, secondaryWindow].compactMap { $0 } }
}
public struct Usage: Decodable {
    public let accountId: String?
    public let planType: String?
    public let rateLimit: RateLimit?
    public let codeReviewRateLimit: RateLimit?
    public let additionalRateLimits: [AdditionalLimit]?
    public var planLabel: String {
        switch planType?.lowercased() {
        case "pro": return "Pro 20x"
        case "prolite": return "Pro 5x"
        case "promax": return "Pro 50x"
        case "plus": return "Plus"
        case nil: return "—"
        default: return planType!.capitalized
        }
    }
    public struct AdditionalLimit: Decodable {
        public let limitName: String?
        public let rateLimit: RateLimit?
    }
    public var rows: [(String, QuotaWindow)] {
        var result = (rateLimit?.windows ?? []).map { ("Codex", $0) }
        result += (codeReviewRateLimit?.windows ?? []).map { ("代码审查", $0) }
        for extra in additionalRateLimits ?? [] {
            result += (extra.rateLimit?.windows ?? []).map { (extra.limitName ?? "附加额度", $0) }
        }
        return result
    }
    public static func decode(_ data: Data) throws -> Usage {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Usage.self, from: data)
    }
}
public enum MonitorError: LocalizedError {
    case missingLogin, unauthorized, forbidden, throttled, invalidResponse, accountChanged, http(Int)
    public var errorDescription: String? {
        switch self {
        case .missingLogin: return "未找到 ChatGPT 登录凭据，请先在 Codex 登录。"
        case .unauthorized: return "登录已过期，请在 Codex 重新登录后刷新。"
        case .forbidden: return "服务端拒绝访问，请检查账号权限或网络。"
        case .throttled: return "请求受限，已暂停自动刷新 15 分钟。"
        case .invalidResponse: return "额度响应格式异常。"
        case .accountChanged: return "账号已变化，请重新刷新。"
        case .http(let status): return "额度查询失败（HTTP \(status)）。"
        }
    }
}
public struct Credentials: Codable, Equatable {
    public init(accessToken: String, accountId: String) {
        self.accessToken = accessToken
        self.accountId = accountId
    }
    public let accessToken: String
    public let accountId: String
}
// Never forward bearer credentials through redirects or persist HTTP caches/cookies.
public final class UsageClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    public func fetch(credentials: Credentials) async throws -> Usage {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 25
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexIsland/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MonitorError.invalidResponse }
        switch http.statusCode {
        case 200: break
        case 401: throw MonitorError.unauthorized
        case 403: throw MonitorError.forbidden
        case 429: throw MonitorError.throttled
        default: throw MonitorError.http(http.statusCode)
        }
        guard data.count < 2_000_000 else { throw MonitorError.invalidResponse }
        let usage: Usage
        do { usage = try Usage.decode(data) } catch { throw MonitorError.invalidResponse }
        if let id = usage.accountId, id != credentials.accountId { throw MonitorError.accountChanged }
        return usage
    }
}
