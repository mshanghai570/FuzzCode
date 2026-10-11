import XCTest
@testable import FuzzCodeCore

final class KeychainSecurityTests: XCTestCase {
    
    func testRedactSecretProtectsCredentials() {
        let key = "sk-proj-abc123456789xyz"
        let redacted = KeychainService.redactSecret(key)
        
        XCTAssertFalse(redacted.contains("abc123456789"))
        XCTAssertTrue(redacted.contains("••••"))
        XCTAssertTrue(redacted.hasPrefix("sk-"))
        XCTAssertTrue(redacted.hasSuffix("xyz (\(key.count) chars)"))
    }
    
    func testRedactShortSecret() {
        let shortKey = "secret"
        let redacted = KeychainService.redactSecret(shortKey)
        XCTAssertEqual(redacted, "••••••")
    }
    
    func testRedactNilOrEmpty() {
        XCTAssertEqual(KeychainService.redactSecret(nil), "[None]")
        XCTAssertEqual(KeychainService.redactSecret(""), "[None]")
    }
}
