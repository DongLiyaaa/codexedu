import Foundation
import QuotaCore

@main struct QuotaCheck {
    static func main() async throws {
        func decode(_ text: String) throws -> Usage { try Usage.decode(Data(text.utf8)) }
        func check(_ passed: Bool, _ label: String) {
            guard passed else { fatalError("FAIL: \(label)") }
            print("PASS: \(label)")
        }
        let usage = try decode(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":48,"limit_window_seconds":604800,"reset_at":1},"secondary_window":null}}"#)
        check(usage.rateLimit?.primaryWindow?.remaining == 52, "used → remaining")
        check(usage.rateLimit?.primaryWindow?.title == "1 周额度", "dynamic window duration")
        check(usage.rateLimit?.primaryWindow?.resetDescription(now: Date()) == "等待服务端确认重置", "reset never fabricates restored quota")
        check(try decode("{}").rows.isEmpty, "missing quota is unknown")
        check(try decode(#"{"rate_limit":{"primary_window":{"used_percent":120}}}"#).rateLimit?.primaryWindow?.remaining == 0, "over-limit clamped")
        check(try decode(#"{"additional_rate_limits":[{"limit_name":"extra","rate_limit":{"primary_window":{"used_percent":20}}}]}"#).rows.count == 1, "additional windows")
        var rejected = false
        do { _ = try decode(#"{"rate_limit":{"primary_window":{"used_percent":"unknown"}}}"#) } catch { rejected = true }
        check(rejected, "invalid schema rejected")
        for (raw, expected) in [("pro", "Pro 20x"), ("prolite", "Pro 5x"), ("promax", "Pro 50x"), ("plus", "Plus")] {
            check(try decode("{\"plan_type\":\"\(raw)\"}").planLabel == expected, "plan label: \(raw)")
        }
    }
}
