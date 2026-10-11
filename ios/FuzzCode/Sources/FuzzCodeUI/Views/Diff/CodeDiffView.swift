import SwiftUI
import FuzzCodeCore

public struct CodeDiffView: View {
    public let summary: GitStatusSummary
    @Environment(\.dismiss) var dismiss
    @State private var selectedFile: GitFileDiff?
    @State private var diffViewMode: DiffViewMode = .unified
    @State private var followUpPrompt: String = ""
    
    public enum DiffViewMode: String, CaseIterable {
        case unified = "Unified"
        case split = "Side-by-Side"
    }
    
    public init(summary: GitStatusSummary) {
        self.summary = summary
        self._selectedFile = State(initialValue: summary.changedFiles.first)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    branchAndStatHeader
                    fileSelectorStrip
                    
                    if let file = selectedFile {
                        diffContentView(file)
                    } else {
                        emptyDiffState
                    }
                }
            }
            .navigationTitle("Code Diff Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(FuzzTheme.acidGreen)
                }
            }
        }
    }
    
    private var branchAndStatHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(FuzzTheme.electricPurple)
                Text(summary.branch)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.textPrimary)
            }
            Spacer()
            
            HStack(spacing: 8) {
                Text("+\(summary.changedFiles.reduce(0) { $0 + $1.additions })")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.acidGreen)
                Text("-\(summary.changedFiles.reduce(0) { $0 + $1.deletions })")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.clippingRed)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(FuzzTheme.surfaceRaised)
            .cornerRadius(6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(FuzzTheme.surface)
    }
    
    private var fileSelectorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(summary.changedFiles) { file in
                    Button(action: {
                        selectedFile = file
                        FuzzTheme.playStompFeedback()
                    }) {
                        HStack(spacing: 6) {
                            fileStatusBadge(file.status)
                            Text(file.filePath)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(selectedFile?.id == file.id ? FuzzTheme.acidGreen : FuzzTheme.textSecondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(selectedFile?.id == file.id ? FuzzTheme.surfaceRaised : FuzzTheme.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(selectedFile?.id == file.id ? FuzzTheme.acidGreen : FuzzTheme.border, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(FuzzTheme.surface.opacity(0.6))
    }
    
    private func fileStatusBadge(_ status: GitFileStatus) -> some View {
        Text(status.rawValue.prefix(1).uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(status == .added ? FuzzTheme.acidGreen : (status == .deleted ? FuzzTheme.clippingRed : FuzzTheme.warningAmber))
    }
    
    private func diffContentView(_ file: GitFileDiff) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                let lines = file.patch.components(separatedBy: "\n")
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    diffLineRow(line)
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color(red: 10/255, green: 11/255, blue: 14/255))
    }
    
    private func diffLineRow(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(FuzzTheme.acidBright)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(FuzzTheme.acidGreen.opacity(0.12))
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(FuzzTheme.clippingRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
                    .background(FuzzTheme.clippingRed.opacity(0.12))
            } else if line.hasPrefix("@@") {
                Text(line)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.electricPurple)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(FuzzTheme.electricPurple.opacity(0.1))
            } else {
                Text(line)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(FuzzTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 2)
            }
        }
    }
    
    private var emptyDiffState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 32))
                .foregroundColor(FuzzTheme.acidGreen)
            Text("Working tree clean")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(FuzzTheme.textSecondary)
            Spacer()
        }
    }
}
