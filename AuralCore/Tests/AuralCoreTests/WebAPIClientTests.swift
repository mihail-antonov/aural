import Foundation
import Testing
@testable import AuralCore

struct WebAPIClientTests {
    @Test func retryAfterReadsSecondsOrFallsBack() {
        #expect(WebAPIClient.retryAfter("42") == 42)
        #expect(WebAPIClient.retryAfter(" 7 ") == 7)
        #expect(WebAPIClient.retryAfter(nil) == 2)
        #expect(WebAPIClient.retryAfter("Wed, 21 Oct 2026 07:28:00 GMT") == 2)
        #expect(WebAPIClient.retryAfter("-1") == 2)
    }

    @Test func rateLimitMessageSaysHowLongToWait() {
        let now = Date(timeIntervalSince1970: 0)
        #expect(WebAPIError.describeWait(until: now + 40, now: now) == "40 seconds")
        #expect(WebAPIError.describeWait(until: now + 1, now: now) == "1 second")
        #expect(WebAPIError.describeWait(until: now + 61, now: now) == "2 minutes")
        #expect(WebAPIError.describeWait(until: now + 3600, now: now) == "1 hour")
        #expect(WebAPIError.describeWait(until: now + 80_000, now: now) == "23 hours")
    }
}
