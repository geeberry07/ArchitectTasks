import Foundation

/// A detected issue or opportunity in the codebase
public struct Finding: Codable, Identifiable, Sendable {
    public var id: UUID
    public var type: FindingType
    public var location: SourceLocation
    public var severity: Severity
    public var context: [String: String]
    public var message: String
    
    public init(
        type: FindingType,
        location: SourceLocation,
        severity: Severity = .warning,
        context: [String: String] = [:],
        message: String
    ) {
        self.id = UUID()
        self.type = type
        self.location = location
        self.severity = severity
        self.context = context
        self.message = message
    }
    
    // MARK: - Finding Types
    
    public enum FindingType: String, Codable, Sendable {
        // Structural gaps
        case missingBinding
        case unusedDependency
        case orphanedView
        case circularReference
        
        // Quality signals
        case untested
        case undocumented
        case highComplexity
        case duplicatedLogic
        case deadCode
        case namingViolation
        case unusedImport
        case securityIssue
        
        // Architecture violations
        case moduleBoundaryViolation
        case layerViolation
        case missingAbstraction
        
        // SwiftUI specific
        case missingStateObject
        case missingEnvironmentObject
        case viewWithoutPreview
    }
    
    // MARK: - Severity
    
    public enum Severity: Int, Codable, Comparable, Sendable {
        case info = 0
        case warning = 1
        case error = 2
        case critical = 3
        
        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}
