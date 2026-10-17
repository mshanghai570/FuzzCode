import Foundation/// Bounded text workspace access. No symlinks, shell execution, or outside paths.
public struct WorkspaceManager: Sendable {
    public static let maxReadBytes = 200_000
    public static let maxListEntries = 500
    public static let maxWorkspaceBytes = 20_000_000
    public let root: URL
    private var fileManager: FileManager { .default }
    private var baselineURL: URL {
        root.deletingLastPathComponent().appendingPathComponent(".\(root.lastPathComponent)-fuzzcode-baseline.json")
    }

    public init(root: URL, fileManager: FileManager = .default) throws {
        if (try? fileManager.attributesOfItem(atPath: root.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
            throw WorkspaceError.pathEscapesRoot
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = URL(fileURLWithPath: root.resolvingSymlinksInPath().standardizedFileURL.path, isDirectory: true)
        try validateMetadataPath()
        if !fileManager.fileExists(atPath: baselineURL.path) { try captureBaseline() }
    }

    public static func defaultRoot(workspaceId: String) -> URL {
        let safeID = String(workspaceId.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }.prefix(128))
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FuzzCode/workspaces", isDirectory: true)
            .appendingPathComponent(safeID.isEmpty ? "workspace" : safeID, isDirectory: true)
    }

    public enum WorkspaceError: Error, LocalizedError, Equatable {
        case pathEscapesRoot
        case notFound(String)
        case unreadable(String)
        case tooLarge(String)
        case patchFailed(String)
        public var errorDescription: String? {
            switch self {
            case .pathEscapesRoot: return "Path escapes the workspace sandbox or contains a symlink."
            case .notFound(let path): return "File not found: \(path)"
            case .unreadable(let path): return "File is not readable: \(path)"
            case .tooLarge(let path): return "Workspace operation exceeds its size limit: \(path)"
            case .patchFailed(let reason): return "Patch failed: \(reason)"
            }
        }
    }

    func resolved(_ path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\0") else { throw WorkspaceError.pathEscapesRoot }
        let target = root.appendingPathComponent(path).standardizedFileURL
        guard target.path == root.path || target.path.hasPrefix(root.path + "/") else { throw WorkspaceError.pathEscapesRoot }
        // Check every component, including dangling links; resolving only the final URL
        // would otherwise allow writes through a missing child of an outside symlink.
        var current = root
        if (try? fileManager.attributesOfItem(atPath: current.path)[.type] as? FileAttributeType) == .typeSymbolicLink {
            throw WorkspaceError.pathEscapesRoot
        }
        for component in relativeString(of: target).split(separator: "/") where component != "." {
            current.appendPathComponent(String(component))
            if let attributes = try? fileManager.attributesOfItem(atPath: current.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw WorkspaceError.pathEscapesRoot }
        }
        guard target.resolvingSymlinksInPath().path == root.path || target.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else {
            throw WorkspaceError.pathEscapesRoot
        }
        return target
    }

    public func relativeString(of url: URL) -> String {
        let path = url.standardizedFileURL.path
        if path == root.path { return "." }
        return path.hasPrefix(root.path + "/") ? String(path.dropFirst(root.path.count + 1)) : path
    }

    public func listFiles(relativePath: String = ".", maxDepth: Int = 3) throws -> [String] {
        let base = try resolved(relativePath)
        guard fileManager.fileExists(atPath: base.path) else { throw WorkspaceError.notFound(relativePath) }
        var results: [String] = []
        var stack = [(base, 0)]
        while let (directory, depth) = stack.popLast() {
            guard depth <= min(max(maxDepth, 0), 20), results.count < Self.maxListEntries else { continue }
            _ = try resolved(relativeString(of: directory))
            let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard results.count < Self.maxListEntries else { break }
                let attributes = try fileManager.attributesOfItem(atPath: entry.path)
                guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else { continue }
                let isDirectory = attributes[.type] as? FileAttributeType == .typeDirectory
                guard isDirectory || attributes[.type] as? FileAttributeType == .typeRegular else { continue }
                results.append(relativeString(of: entry) + (isDirectory ? "/" : ""))
                if isDirectory { stack.append((entry, depth + 1)) }
            }
        }
        return results.sorted()
    }

    public func searchFiles(query: String, maxMatches: Int = 100) throws -> [GitHubSearchMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let limit = min(max(maxMatches, 1), 500)
        var matches: [GitHubSearchMatch] = []
        var totalBytes = 0
        for path in try listFiles(maxDepth: 20) where !path.hasSuffix("/") {
            guard matches.count < limit else { break }
            let url = try resolved(path)
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
            guard size <= Self.maxReadBytes else { continue }
            totalBytes += size
            guard totalBytes <= Self.maxWorkspaceBytes else { throw WorkspaceError.tooLarge("search inventory") }
            guard let content = try? readFile(relativePath: path) else { continue }
            for (offset, line) in content.components(separatedBy: "\n").enumerated() where line.lowercased().contains(needle) {
                matches.append(GitHubSearchMatch(path: path, lineNumber: offset + 1, text: String(line.prefix(500))))
                if matches.count >= limit { break }
            }
        }
        return matches
    }

    public func readFile(relativePath: String) throws -> String {
        let url = try resolved(relativePath)
        guard fileManager.fileExists(atPath: url.path) else { throw WorkspaceError.notFound(relativePath) }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw WorkspaceError.unreadable(relativePath) }
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= Self.maxReadBytes else { throw WorkspaceError.tooLarge(relativePath) }
        let data = try Data(contentsOf: url)
        guard data.count <= Self.maxReadBytes else { throw WorkspaceError.tooLarge(relativePath) }
        guard let text = String(data: data, encoding: .utf8) else { throw WorkspaceError.unreadable(relativePath) }
        return text
    }

    public func writeFile(relativePath: String, content: String) throws {
        try Task.checkCancellation()
        guard content.utf8.count <= Self.maxReadBytes else { throw WorkspaceError.tooLarge(relativePath) }
        let target = try resolved(relativePath)
        guard target.path != root.path else { throw WorkspaceError.unreadable(relativePath) }
        try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = try resolved(relativePath)
        try Task.checkCancellation()
        try content.write(to: target, atomically: true, encoding: .utf8)
    }

    public func previewWrite(relativePath: String, content: String) throws -> String {
        let target = try resolved(relativePath)
        guard target.path != root.path else { throw WorkspaceError.unreadable(relativePath) }
        guard content.utf8.count <= Self.maxReadBytes else { throw WorkspaceError.tooLarge(relativePath) }
        let original = fileManager.fileExists(atPath: target.path) ? try readFile(relativePath: relativePath) : nil
        return diff(path: relativePath, before: original, after: content).patch
    }

    private struct PatchEdit {
        let path: String
        let original: String?
        let content: String
    }

    /// Validates the entire patch and returns the exact text shown before approval.
    public func previewUnifiedPatch(_ patch: String) throws -> String {
        _ = try preparePatch(patch)
        return patch
    }

    /// Every path and hunk is checked before any mutation. Unsupported deletions,
    /// renames, binary patches and no-newline markers are rejected explicitly.
    @discardableResult
    public func applyUnifiedPatch(_ patch: String) throws -> String {
        let edits = try preparePatch(patch)
        try Task.checkCancellation()
        var applied: [PatchEdit] = []
        do {
            for edit in edits {
                try writeFile(relativePath: edit.path, content: edit.content)
                applied.append(edit)
            }
        } catch {
            // Best-effort rollback if storage fails after successful prevalidation.
            // Rollback intentionally does not use the cancelled mutation API.
            for edit in applied.reversed() {
                if let original = edit.original {
                    try? original.write(to: resolved(edit.path), atomically: true, encoding: .utf8)
                } else if let target = try? resolved(edit.path) { try? fileManager.removeItem(at: target) }
            }
            throw error
        }
        return "Patched " + edits.map(\.path).joined(separator: ", ") + "."
    }

    private func preparePatch(_ patch: String) throws -> [PatchEdit] {
        guard !patch.isEmpty, patch.utf8.count <= Self.maxWorkspaceBytes else { throw WorkspaceError.tooLarge("patch") }
        var lines = patch.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        var index = 0
        var edits: [PatchEdit] = []
        var paths = Set<String>()
        let regex = try NSRegularExpression(pattern: #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@(?: .*)?$"#)
        func fail(_ message: String) -> WorkspaceError { .patchFailed(message) }
        func clean(_ header: String, prefix: String) throws -> String {
            let value = String(header.dropFirst(4))
            guard !value.isEmpty, !value.contains("\t"), !value.contains("\0") else { throw fail("Unsupported file header.") }
            return value.hasPrefix(prefix) ? String(value.dropFirst(2)) : value
        }
        while index < lines.count {
            if lines[index].hasPrefix("diff --git ") { index += 1 }
            if index < lines.count, lines[index].hasPrefix("index ") { index += 1 }
            guard index + 1 < lines.count, lines[index].hasPrefix("--- "), lines[index + 1].hasPrefix("+++ ") else { throw fail("Expected file headers.") }
            let oldPath = try clean(lines[index], prefix: "a/")
            let path = try clean(lines[index + 1], prefix: "b/")
            guard path != "/dev/null", oldPath == "/dev/null" || oldPath == path else { throw fail("Deletion and rename patches are unsupported.") }
            let target = try resolved(path)
            guard paths.insert(target.path).inserted else { throw fail("Duplicate target file.") }
            let isNew = oldPath == "/dev/null"
            if isNew, fileManager.fileExists(atPath: target.path) { throw fail("New-file target already exists.") }
            let original = isNew ? nil : try readFile(relativePath: path)
            var oldLines = original?.components(separatedBy: "\n") ?? []
            let trailingNewline = original?.hasSuffix("\n") ?? false
            if trailingNewline { oldLines.removeLast() }
            var output: [String] = []
            var cursor = 0
            var hunkCount = 0
            index += 2
            while index < lines.count, lines[index].hasPrefix("@@") {
                let header = lines[index]
                guard let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)) else { throw fail("Malformed hunk header.") }
                func number(_ group: Int, fallback: Int) -> Int {
                    guard let range = Range(match.range(at: group), in: header) else { return fallback }
                    return Int(header[range]) ?? -1
                }
                let oldStart = number(1, fallback: -1), oldCount = number(2, fallback: 1)
                let newStart = number(3, fallback: -1), newCount = number(4, fallback: 1)
                guard oldStart >= 0, newStart >= 0, oldCount >= 0, newCount >= 0,
                      oldCount == 0 || oldStart > 0, newCount == 0 || newStart > 0 else { throw fail("Invalid hunk coordinates.") }
                let start = oldCount == 0 ? oldStart : oldStart - 1
                guard start >= cursor, start <= oldLines.count, oldCount <= oldLines.count - start else { throw fail("Overlapping or out-of-range hunk.") }
                output.append(contentsOf: oldLines[cursor..<start])
                guard (newCount == 0 ? newStart : newStart - 1) == output.count else { throw fail("Inconsistent new hunk coordinates.") }
                cursor = start
                var removed = 0, added = 0
                index += 1
                while index < lines.count, !lines[index].hasPrefix("@@"), !lines[index].hasPrefix("--- "), !lines[index].hasPrefix("diff --git ") {
                    let line = lines[index]
                    guard let marker = line.first, marker == " " || marker == "-" || marker == "+" else { throw fail("Unsupported or malformed hunk line.") }
                    let text = String(line.dropFirst())
                    if marker != "+" {
                        guard cursor < oldLines.count, oldLines[cursor] == text else { throw fail("Context mismatch in \(path) at line \(cursor + 1).") }
                        cursor += 1; removed += 1
                    }
                    if marker != "-" { output.append(text); added += 1 }
                    index += 1
                }
                guard removed == oldCount, added == newCount else { throw fail("Hunk line counts do not match the header.") }
                hunkCount += 1
            }
            guard hunkCount > 0 else { throw fail("No hunks found.") }
            output.append(contentsOf: oldLines[cursor...])
            let content = output.joined(separator: "\n") + (trailingNewline ? "\n" : "")
            guard content.utf8.count <= Self.maxReadBytes else { throw WorkspaceError.tooLarge(path) }
            edits.append(PatchEdit(path: path, original: original, content: content))
            guard edits.count <= Self.maxListEntries else { throw WorkspaceError.tooLarge("patch file count") }
        }
        guard !edits.isEmpty else { throw fail("No files found.") }
        return edits
    }

    private func validateMetadataPath() throws {
        if let attributes = try? fileManager.attributesOfItem(atPath: baselineURL.path), attributes[.type] as? FileAttributeType != .typeRegular {
            throw WorkspaceError.pathEscapesRoot
        }
    }

    private func snapshot() throws -> [String: String] {
        var snapshot: [String: String] = [:]
        var total = 0
        for path in try listFiles(maxDepth: 20) where !path.hasSuffix("/") {
            let content = try readFile(relativePath: path)
            total += content.utf8.count
            guard total <= Self.maxWorkspaceBytes else { throw WorkspaceError.tooLarge("baseline") }
            snapshot[path] = content
        }
        return snapshot
    }

    /// Explicitly resets the comparison point after a successful repository import.
    public func captureBaseline() throws {
        try validateMetadataPath()
        let data = try JSONEncoder().encode(snapshot())
        try data.write(to: baselineURL, options: .atomic)
    }

    public func reviewedChanges() throws -> [GitHubFileChange] {
        let summary = try changeSummary()
        return try summary.changedFiles.map { file in
            guard file.status != .deleted else { throw WorkspaceError.patchFailed("Deleting files through remote review is not supported.") }
            return GitHubFileChange(path: file.filePath, content: try readFile(relativePath: file.filePath))
        }
    }

    public func changeSummary() throws -> GitStatusSummary {
        try validateMetadataPath()
        let data = try Data(contentsOf: baselineURL)
        guard data.count <= Self.maxWorkspaceBytes * 2 else { throw WorkspaceError.tooLarge("baseline") }
        let baseline = try JSONDecoder().decode([String: String].self, from: data)
        let current = try snapshot()
        let changes = Set(baseline.keys).union(current.keys).sorted().compactMap { path -> GitFileDiff? in
            guard baseline[path] != current[path] else { return nil }
            return diff(path: path, before: baseline[path], after: current[path])
        }
        return GitStatusSummary(branch: "workspace baseline", changedFiles: changes)
    }

    private func diff(path: String, before: String?, after: String?) -> GitFileDiff {
        func lines(_ value: String?) -> [String] {
            guard let value, !value.isEmpty else { return [] }
            var result = value.components(separatedBy: "\n")
            if value.hasSuffix("\n") { result.removeLast() }
            return result
        }
        let old = lines(before), new = lines(after)
        let header = "--- \(before == nil ? "/dev/null" : "a/" + path)\n+++ \(after == nil ? "/dev/null" : "b/" + path)\n@@ -\(old.isEmpty ? 0 : 1),\(old.count) +\(new.isEmpty ? 0 : 1),\(new.count) @@\n"
        let patch = header + old.map { "-" + $0 }.joined(separator: "\n") + (old.isEmpty ? "" : "\n") + new.map { "+" + $0 }.joined(separator: "\n")
        return GitFileDiff(filePath: path, status: before == nil ? .added : after == nil ? .deleted : .modified, additions: new.count, deletions: old.count, patch: patch)
    }
}
