import XCTest
@testable import FuzzCodeCore

final class MCPConnectorTests: XCTestCase {
    
    func testMCPServerConfigDefaultValues() {
        let server = MCPServerConfig(
            name: "PostgreSQL MCP",
            transport: .sse,
            endpointURLString: "http://localhost:8080/sse"
        )
        
        XCTAssertEqual(server.name, "PostgreSQL MCP")
        XCTAssertEqual(server.transport, .sse)
        XCTAssertTrue(server.isEnabled)
        XCTAssertFalse(server.isConnected)
    }
    
    func testMCPToolSchemaEncoding() throws {
        let schema = MCPToolInputSchema(
            type: "object",
            properties: [
                "sql": MCPToolParameterProperty(type: "string", description: "Query to execute")
            ],
            required: ["sql"]
        )
        let tool = MCPTool(name: "query", description: "Execute SQL query", inputSchema: schema)
        
        XCTAssertEqual(tool.name, "query")
        XCTAssertEqual(tool.inputSchema.required, ["sql"])
    }
}
