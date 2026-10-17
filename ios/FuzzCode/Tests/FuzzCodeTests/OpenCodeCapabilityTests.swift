import XCTest
@testable import FuzzCodeCore

final class OpenCodeCapabilityTests: XCTestCase {
    
    func testCapabilitySetContainsAllCoreFeatures() async {
        let host = OpenCodeHostConfig(
            displayName: "Test Host",
            hostURLString: "https://agent.local:4096",
            capabilities: [.sessions, .streaming, .toolEvents, .cancellation, .fileDiffs, .permissionRequests, .gitStatus]
        )
        
        let client = OpenCodeClient(hostConfig: host)
        let capabilities = await client.supportedCapabilities
        XCTAssertTrue(capabilities.contains(.streaming))
        XCTAssertTrue(capabilities.contains(.permissionRequests))
        XCTAssertTrue(capabilities.contains(.fileDiffs))
    }
    
    func testPermissionRequestRiskLevelDefaults() {
        let request = PermissionRequest(
            toolName: "execute_bash",
            commandOrPath: "rm -rf /tmp/cache",
            riskLevel: .destructive
        )
        
        XCTAssertEqual(request.riskLevel, .destructive)
        XCTAssertEqual(request.toolName, "execute_bash")
    }
}
