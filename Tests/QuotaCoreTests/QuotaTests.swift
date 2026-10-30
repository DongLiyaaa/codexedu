import XCTest
@testable import QuotaCore

final class QuotaTests: XCTestCase {
    func usage(_ json: String) throws -> Usage { try Usage.decode(Data(json.utf8)) }
    func testRealResponseShape() throws {
        let value = try usage(#"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":48,"limit_window_seconds":604800,"reset_at":1793805754},"secondary_window":null}}"#)
        XCTAssertEqual(value.rateLimit?.primaryWindow?.remaining, 52)
        XCTAssertEqual(value.rateLimit?.primaryWindow?.title, "1 周额度")
        XCTAssertEqual(value.rows.count, 1)
    }
    func testMissingIsNotZero() throws {
        XCTAssertTrue(try usage(#"{"rate_limit":null}"#).rows.isEmpty)
        XCTAssertNil(try usage("{}").rateLimit)
    }
    func testClampAndResetDoesNotRestoreQuota() throws {
        let window = try XCTUnwrap(usage(#"{"rate_limit":{"primary_window":{"used_percent":120,"reset_at":1}}}"#).rateLimit?.primaryWindow)
        XCTAssertEqual(window.remaining, 0)
        XCTAssertEqual(window.resetDescription(now: Date()), "等待服务端确认重置")
    }
    func testAdditionalWindows() throws {
        let value = try usage(#"{"additional_rate_limits":[{"limit_name":"other","rate_limit":{"primary_window":{"used_percent":20}}}]}"#)
        XCTAssertEqual(value.rows.count, 1)
        XCTAssertEqual(value.rows.first?.0, "other")
    }
    func testInvalidWindowRejected() {
        XCTAssertThrowsError(try usage(#"{"rate_limit":{"primary_window":{"used_percent":"unknown"}}}"#))
    }
}
