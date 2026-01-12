import Foundation

// MARK: - Approval Policy

/// Defines rules for automatic task approval/rejection.
/// Policies are evaluated in order; first match wins.
public struct ApprovalPolicy: Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var description: String
    public var rules: [PolicyRule]
    public var defaultDecision: PolicyDecision
    public var isEnabled: Bool
    
    public init(
        name: String,
        description: String = "",
        rules: [PolicyRule],
        defaultDecision: PolicyDecision = .requireHuman
    ) {
        self.id = UUID()
        self.name = name
        self.description = description
        self.rules = rules
        self.defaultDecision = defaultDecision
        self.isEnabled = true
    }
    
    /// Evaluate a task against this policy
    public func evaluate(_ task: AgentTask) -> PolicyDecision {
        for rule in rules where rule.matches(task) {
            return rule.decision
        }
        return defaultDecision
    }
}

// MARK: - Policy Rule

public struct PolicyRule: Codable, Sendable {
    public var condition: PolicyCondition
    public var decision: PolicyDecision
    public var reason: String?
    
    public init(
        condition: PolicyCondition,
        decision: PolicyDecision,
        reason: String? = nil
    ) {
        self.condition = condition
        self.decision = decision
        self.reason = reason
    }
    
    public func matches(_ task: AgentTask) -> Bool {
        condition.matches(task)
    }
}

// MARK: - Policy Condition

public indirect enum PolicyCondition: Codable, Sendable {
    /// Match by intent category
    case intentCategory(IntentCategory)
    
    /// Match by specific intent type
    case intentType(String)
    
    /// Match by scope type
    case scopeType(ScopeType)
    
    /// Match by confidence threshold
    case confidenceAbove(Double)
    case confidenceBelow(Double)
    
    /// Match by file pattern
    case filePattern(String)
    
    /// Match by step count
    case maxSteps(Int)
    
    /// Combine conditions
    case all([PolicyCondition])
    case any([PolicyCondition])
    case not(PolicyCondition)
    
    public func matches(_ task: AgentTask) -> Bool {
        switch self {
        case .intentCategory(let category):
            return task.intent.category == category
            
        case .intentType(let type):
            return String(describing: task.intent).contains(type)
            
        case .scopeType(let scopeType):
            switch (task.scope, scopeType) {
            case (.file, .file), (.module, .module), 
                 (.feature, .feature), (.project, .project):
                return true
            default:
                return false
            }
            
        case .confidenceAbove(let threshold):
            return task.confidence > threshold
            
        case .confidenceBelow(let threshold):
            return task.confidence < threshold
            
        case .filePattern(let pattern):
            switch task.scope {
            case .file(let path):
                return path.contains(pattern) || matchesGlob(path, pattern: pattern)
            default:
                return false
            }
            
        case .maxSteps(let max):
            return task.steps.count <= max
            
        case .all(let conditions):
            return conditions.allSatisfy { $0.matches(task) }
            
        case .any(let conditions):
            return conditions.contains { $0.matches(task) }
            
        case .not(let condition):
            return !condition.matches(task)
        }
    }
    
    private func matchesGlob(_ path: String, pattern: String) -> Bool {
        // Simple glob matching
        if pattern.hasPrefix("*") {
            return path.hasSuffix(String(pattern.dropFirst()))
        }
        if pattern.hasSuffix("*") {
            return path.hasPrefix(String(pattern.dropLast()))
        }
        return path == pattern
    }
}

/// Box for recursive types (Codable workaround) - kept for API compatibility
public struct Box<T: Codable & Sendable>: Codable, Sendable {
    public var value: T
    public init(_ value: T) { self.value = value }
}

public enum ScopeType: String, Codable, Sendable {
    case file, module, feature, project
}

// MARK: - Policy Decision

public enum PolicyDecision: String, Codable, Sendable {
    case allow          // Auto-approve
    case deny           // Auto-reject
    case requireHuman   // Must have human approval
}

// MARK: - Built-in Policies

extension ApprovalPolicy {
    
    /// Conservative: only auto-approve documentation tasks
    public static let conservative = ApprovalPolicy(
        name: "Conservative",
        description: "Only auto-approve documentation and comments",
        rules: [
            PolicyRule(
                condition: .intentCategory(.documentation),
                decision: .allow,
                reason: "Documentation changes are low-risk"
            ),
            PolicyRule(
                condition: .intentCategory(.architecture),
                decision: .deny,
                reason: "Architecture changes require review"
            )
        ],
        defaultDecision: .requireHuman
    )
    
    /// Moderate: auto-approve single-file, high-confidence tasks
    public static let moderate = ApprovalPolicy(
        name: "Moderate",
        description: "Auto-approve high-confidence, single-file changes",
        rules: [
            PolicyRule(
                condition: .all([
                    .scopeType(.file),
                    .confidenceAbove(0.8),
                    .maxSteps(3)
                ]),
                decision: .allow,
                reason: "High-confidence, small scope"
            ),
            PolicyRule(
                condition: .intentCategory(.architecture),
                decision: .deny,
                reason: "Architecture changes require review"
            ),
            PolicyRule(
                condition: .scopeType(.project),
                decision: .deny,
                reason: "Project-wide changes require review"
            )
        ],
        defaultDecision: .requireHuman
    )
    
    /// Permissive: auto-approve most things except architecture
    public static let permissive = ApprovalPolicy(
        name: "Permissive",
        description: "Auto-approve most changes, deny architecture",
        rules: [
            PolicyRule(
                condition: .intentCategory(.architecture),
                decision: .requireHuman,
                reason: "Architecture changes need review"
            ),
            PolicyRule(
                condition: .confidenceBelow(0.5),
                decision: .requireHuman,
                reason: "Low confidence needs review"
            )
        ],
        defaultDecision: .allow
    )
    
    /// CI: report only, never auto-approve
    public static let ci = ApprovalPolicy(
        name: "CI",
        description: "Report findings but never auto-approve",
        rules: [],
        defaultDecision: .requireHuman
    )
    
    /// Strict: deny everything, human must approve all
    public static let strict = ApprovalPolicy(
        name: "Strict",
        description: "Require human approval for everything",
        rules: [],
        defaultDecision: .requireHuman
    )
}
