import Foundation

// MARK: - Rule Configuration

/// Team-configurable ruleset for customizing analysis behavior.
/// Allows enabling/disabling rules, setting severity levels, and configuring thresholds.
public struct RuleConfiguration: Codable, Sendable, Equatable {
    
    /// Unique identifier for this configuration
    public let id: String
    
    /// Human-readable name
    public let name: String
    
    /// Description of this configuration
    public let description: String?
    
    /// Version for tracking changes
    public let version: String
    
    /// Individual rule settings
    public var rules: [String: RuleSetting]
    
    /// Global settings that apply to all rules
    public var globalSettings: GlobalSettings
    
    /// File patterns to include in analysis
    public var includePatterns: [String]
    
    /// File patterns to exclude from analysis
    public var excludePatterns: [String]
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        version: String = "1.0.0",
        rules: [String: RuleSetting] = [:],
        globalSettings: GlobalSettings = .default,
        includePatterns: [String] = ["**/*.swift"],
        excludePatterns: [String] = ["**/.build/**", "**/DerivedData/**", "**/*.generated.swift"]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.version = version
        self.rules = rules
        self.globalSettings = globalSettings
        self.includePatterns = includePatterns
        self.excludePatterns = excludePatterns
    }
}

// MARK: - Rule Setting

/// Configuration for an individual rule
public struct RuleSetting: Codable, Sendable, Equatable {
    
    /// Whether the rule is enabled
    public var enabled: Bool
    
    /// Severity level for findings from this rule
    public var severity: SeverityLevel
    
    /// Rule-specific thresholds and parameters
    public var parameters: [String: ParameterValue]
    
    /// Optional custom message template
    public var messageTemplate: String?
    
    /// Tags for categorization
    public var tags: [String]
    
    public init(
        enabled: Bool = true,
        severity: SeverityLevel = .warning,
        parameters: [String: ParameterValue] = [:],
        messageTemplate: String? = nil,
        tags: [String] = []
    ) {
        self.enabled = enabled
        self.severity = severity
        self.parameters = parameters
        self.messageTemplate = messageTemplate
        self.tags = tags
    }
    
    /// Create a disabled rule setting
    public static func disabled() -> RuleSetting {
        RuleSetting(enabled: false)
    }
    
    /// Create an enabled rule with custom severity
    public static func enabled(severity: SeverityLevel) -> RuleSetting {
        RuleSetting(enabled: true, severity: severity)
    }
}

// MARK: - Severity Level

/// Configurable severity levels for rules
public enum SeverityLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case ignore = "ignore"
    case info = "info"
    case warning = "warning"
    case error = "error"
    case critical = "critical"
    
    public static func < (lhs: SeverityLevel, rhs: SeverityLevel) -> Bool {
        let order: [SeverityLevel] = [.ignore, .info, .warning, .error, .critical]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
    
    /// Convert to Finding.Severity
    public var toFindingSeverity: Finding.Severity {
        switch self {
        case .ignore: return .info
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }
}

// MARK: - Parameter Value

/// Type-safe parameter values for rule configuration
public enum ParameterValue: Codable, Sendable, Equatable {
    case int(Int)
    case double(Double)
    case string(String)
    case bool(Bool)
    case array([ParameterValue])
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let array = try? container.decode([ParameterValue].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown parameter type")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        }
    }
    
    public var intValue: Int? {
        if case .int(let v) = self { return v }
        return nil
    }
    
    public var doubleValue: Double? {
        if case .double(let v) = self { return v }
        if case .int(let v) = self { return Double(v) }
        return nil
    }
    
    public var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }
    
    public var boolValue: Bool? {
        if case .bool(let v) = self { return v }
        return nil
    }
}

// MARK: - Global Settings

/// Settings that apply across all rules
public struct GlobalSettings: Codable, Sendable, Equatable {
    
    /// Minimum severity to report
    public var minimumSeverity: SeverityLevel
    
    /// Maximum findings per file
    public var maxFindingsPerFile: Int?
    
    /// Maximum total findings
    public var maxTotalFindings: Int?
    
    /// Whether to fail on any error-level findings
    public var failOnError: Bool
    
    /// Whether to fail on any critical-level findings
    public var failOnCritical: Bool
    
    /// Parallel analysis enabled
    public var parallelAnalysis: Bool
    
    public init(
        minimumSeverity: SeverityLevel = .info,
        maxFindingsPerFile: Int? = nil,
        maxTotalFindings: Int? = nil,
        failOnError: Bool = false,
        failOnCritical: Bool = true,
        parallelAnalysis: Bool = true
    ) {
        self.minimumSeverity = minimumSeverity
        self.maxFindingsPerFile = maxFindingsPerFile
        self.maxTotalFindings = maxTotalFindings
        self.failOnError = failOnError
        self.failOnCritical = failOnCritical
        self.parallelAnalysis = parallelAnalysis
    }
    
    public static let `default` = GlobalSettings()
    
    public static let strict = GlobalSettings(
        minimumSeverity: .info,
        failOnError: true,
        failOnCritical: true
    )
    
    public static let lenient = GlobalSettings(
        minimumSeverity: .warning,
        failOnError: false,
        failOnCritical: true
    )
}
