import Foundation
import ArchitectCore

/// Scans a project directory and runs analyzers on Swift files
public final class ProjectScanner: @unchecked Sendable {
    private let pipeline: AnalyzerPipeline
    private let fileManager: FileManager
    
    public init(analyzers: [Analyzer]) {
        self.pipeline = AnalyzerPipeline(analyzers: analyzers)
        self.fileManager = .default
    }
    
    /// Convenience initializer with default analyzers
    public convenience init() {
        self.init(analyzers: [
            SwiftUIBindingAnalyzer(),
            ComplexityAnalyzer()
        ])
    }
    
    /// Convenience initializer with custom complexity thresholds
    public convenience init(complexityThresholds: ComplexityAnalyzer.Thresholds) {
        self.init(analyzers: [
            SwiftUIBindingAnalyzer(),
            ComplexityAnalyzer(thresholds: complexityThresholds)
        ])
    }
    
    /// Scan a project and return all findings
    public func scan(projectPath: String) async throws -> [Finding] {
        let swiftFiles = try findSwiftFiles(in: projectPath)
        var allFindings: [Finding] = []
        
        for file in swiftFiles {
            let content = try String(contentsOfFile: file, encoding: .utf8)
            let relativePath = makeRelativePath(file, to: projectPath)
            let findings = try pipeline.analyze(fileAt: relativePath, content: content)
            allFindings.append(contentsOf: findings)
        }
        
        return allFindings
    }
    
    // MARK: - Private
    
    private func findSwiftFiles(in directory: String) throws -> [String] {
        var swiftFiles: [String] = []
        let url = URL(fileURLWithPath: directory)
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        
        for case let fileURL as URL in enumerator {
            // Skip common non-source directories
            let pathComponents = fileURL.pathComponents
            if pathComponents.contains(".build") ||
               pathComponents.contains("DerivedData") ||
               pathComponents.contains("Pods") ||
               pathComponents.contains(".git") {
                continue
            }
            
            if fileURL.pathExtension == "swift" {
                swiftFiles.append(fileURL.path)
            }
        }
        
        return swiftFiles
    }
    
    private func makeRelativePath(_ absolutePath: String, to basePath: String) -> String {
        let base = basePath.hasSuffix("/") ? basePath : basePath + "/"
        if absolutePath.hasPrefix(base) {
            return String(absolutePath.dropFirst(base.count))
        }
        return absolutePath
    }
}
