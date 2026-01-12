import Foundation
import ArchitectCore

/// Base protocol for all code analyzers
public protocol Analyzer: Sendable {
    /// The types of findings this analyzer can produce
    var supportedFindingTypes: [Finding.FindingType] { get }
    
    /// Analyze a single file and return findings
    func analyze(fileAt path: String, content: String) throws -> [Finding]
}

/// Aggregates multiple analyzers
public final class AnalyzerPipeline: Sendable {
    private let analyzers: [Analyzer]
    
    public init(analyzers: [Analyzer]) {
        self.analyzers = analyzers
    }
    
    public func analyze(fileAt path: String, content: String) throws -> [Finding] {
        var allFindings: [Finding] = []
        
        for analyzer in analyzers {
            let findings = try analyzer.analyze(fileAt: path, content: content)
            allFindings.append(contentsOf: findings)
        }
        
        return allFindings
    }
}
