import Foundation

/// A native tool prepares a validated operation and a complete approval preview.
/// The engine decides whether to execute it and checks cancellation after approval.
public protocol AgentTool: Sendable {
    var definition: ProviderToolDefinition { get }
    func prepare(arguments: Data, workspace: WorkspaceManager) throws -> PreparedAgentTool
}

public struct PreparedAgentTool: Sendable {
    public let permission: PermissionRequest?
    private let operation: @Sendable () throws -> String

    public init(permission: PermissionRequest? = nil, operation: @Sendable @escaping () throws -> String) {
        self.permission = permission
        self.operation = operation
    }

    public func execute() throws -> String {
        try Task.checkCancellation()
        return try operation()
    }
}

/// The native engine exposes only this fixed, bounded filesystem tool set.
public enum WorkspaceAgentTool: String, CaseIterable, AgentTool {
    case listFiles = "list_files"
    case readFile = "read_file"
    case writeFile = "write_file"
    case applyPatch = "apply_patch"
    case searchFiles = "search_files"

    public var definition: ProviderToolDefinition {
        let properties: [String: String]
        let required: [String]
        let description: String
        switch self {
        case .listFiles:
            properties = ["path": "string"]; required = []
            description = "List bounded files in the sandboxed workspace."
        case .readFile:
            properties = ["path": "string"]; required = ["path"]
            description = "Read a bounded UTF-8 workspace file."
        case .writeFile:
            properties = ["path": "string", "content": "string"]; required = ["path", "content"]
            description = "Create or overwrite a workspace file after user approval of its diff."
        case .applyPatch:
            properties = ["patch": "string"]; required = ["patch"]
            description = "Validate and apply a unified patch after user approval. Deletions and renames are unsupported."
        case .searchFiles:
            properties = ["query": "string"]; required = ["query"]
            description = "Search text in the bounded sandboxed repository workspace."
        }
        return ProviderToolDefinition(name: rawValue, description: description, inputSchema: MCPToolInputSchema(
            type: "object", properties: properties.mapValues { MCPToolParameterProperty(type: $0) }, required: required))
    }

    public enum ToolError: Error, LocalizedError {
        case invalidArguments(String)
        case workspaceChanged
        public var errorDescription: String? {
            switch self {
            case .invalidArguments(let detail): return "Invalid tool arguments: \(detail)"
            case .workspaceChanged: return "The file changed while awaiting approval. Request a new preview."
            }
        }
    }

    public func prepare(arguments: Data, workspace: WorkspaceManager) throws -> PreparedAgentTool {
        guard arguments.count <= WorkspaceManager.maxWorkspaceBytes,
              let values = try JSONSerialization.jsonObject(with: arguments) as? [String: Any] else {
            throw ToolError.invalidArguments("expected a bounded JSON object")
        }
        func string(_ key: String) throws -> String {
            guard let value = values[key] as? String else { throw ToolError.invalidArguments("missing \(key)") }
            return value
        }
        switch self {
        case .listFiles:
            if let path = values["path"], !(path is String) { throw ToolError.invalidArguments("path must be a string") }
            let path = values["path"] as? String ?? "."
            return PreparedAgentTool {
                let files = try workspace.listFiles(relativePath: path)
                return files.isEmpty ? "(empty directory)" : files.joined(separator: "\n")
            }
        case .readFile:
            let path = try string("path")
            return PreparedAgentTool { try workspace.readFile(relativePath: path) }
        case .writeFile:
            let path = try string("path"), content = try string("content")
            let preview = try workspace.previewWrite(relativePath: path, content: content)
            let original = try existingText(workspace: workspace, path: path)
            let permission = PermissionRequest(toolName: rawValue, commandOrPath: path,
                fullParameters: ["preview": preview, "path": path, "content": content], riskLevel: .high)
            return PreparedAgentTool(permission: permission) {
                guard try existingText(workspace: workspace, path: path) == original else { throw ToolError.workspaceChanged }
                try workspace.writeFile(relativePath: path, content: content)
                return "Wrote \(path).\n\(preview)"
            }
        case .applyPatch:
            let patch = try string("patch")
            let preview = try workspace.previewUnifiedPatch(patch)
            let permission = PermissionRequest(toolName: rawValue, commandOrPath: "workspace patch",
                fullParameters: ["preview": preview, "patch": patch], riskLevel: .high)
            return PreparedAgentTool(permission: permission) { try workspace.applyUnifiedPatch(patch) }
        case .searchFiles:
            let query = try string("query")
            return PreparedAgentTool {
                let matches = try workspace.searchFiles(query: query)
                guard !matches.isEmpty else { return "No matching lines." }
                return matches.map { "\($0.path):\($0.lineNumber): \($0.text)" }.joined(separator: "\n")
            }
        }
    }
}

private func existingText(workspace: WorkspaceManager, path: String) throws -> String? {
    do { return try workspace.readFile(relativePath: path) }
    catch WorkspaceManager.WorkspaceError.notFound { return nil }
}
