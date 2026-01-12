import Foundation

// MARK: - Policy JSON Schema

/// JSON-serializable policy format for external configuration.
/// Allows teams to define policies in version-controlled JSON files.
public struct PolicySchema: Codable, Sendable {
    public var name: String
    public var description: String?
    public var version: String
    public var rules: [RuleSchema]
    public var defaultDecision: String  // "allow", "deny", "requireHuman"
    
    public init(
        name: String,
        description: String? = nil,
        version: String = "1.0",
        rules: [RuleSchema],
        defaultDecision: String = "requireHuman"
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.rules = rules
        self.defaultDecision = defaultDecision
    }
    
    /// Convert to runtime ApprovalPolicy
    public func toPolicy() throws -> ApprovalPolicy {
        let policyRules = try rules.map { try $0.toRule() }
        
        guard let decision = PolicyDecision(rawValue: defaultDecision) else {
            throw PolicySchemaError.invalidDecision(defaultDecision)
        }
        
        return ApprovalPolicy(
            name: name,
            description: description ?? "",
            rules: policyRules,
            defaultDecision: decision
        )
    }
}

// MARK: - Rule Schema

public struct RuleSchema: Codable, Sendable {
    public var condition: ConditionSchema
    public var decision: String
    public var reason: String?
    
    public func toRule() throws -> PolicyRule {
        guard let dec = PolicyDecision(rawValue: decision) else {
            throw PolicySchemaError.invalidDecision(decision)
        }
        
        return PolicyRule(
            condition: try condition.toCondition(),
            decision: dec,
            reason: reason
        )
    }
}

// MARK: - Condition Schema

public struct ConditionSchema: Codable, Sendable {
    public var type: String
    public var value: ConditionValue?
    public var conditions: [ConditionSchema]?
    
    public enum ConditionValue: Codable, Sendable {
        case string(String)
        case number(Double)
        case integer(Int)
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let str = try? container.decode(String.self) {
                self = .string(str)
            } else if let num = try? container.decode(Double.self) {
                self = .number(num)
            } else if let int = try? container.decode(Int.self) {
                self = .integer(int)
            } else {
                throw DecodingError.typeMismatch(
                    ConditionValue.self,
                    .init(codingPath: decoder.codingPath, debugDescription: "Expected string, number, or integer")
                )
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .number(let n): try container.encode(n)
            case .integer(let i): try container.encode(i)
            }
        }
        
        var stringValue: String? {
            if case .string(let s) = self { return s }
            return nil
        }
        
        var doubleValue: Double? {
            switch self {
            case .number(let n): return n
            case .integer(let i): return Double(i)
            default: return nil
            }
        }
        
        var intValue: Int? {
            if case .integer(let i) = self { return i }
            return nil
        }
    }
    
    public func toCondition() throws -> PolicyCondition {
        switch type {
        case "intentCategory":
            guard let str = value?.stringValue,
                  let category = IntentCategory(rawValue: str) else {
                throw PolicySchemaError.invalidValue("intentCategory requires valid category string")
            }
            return .intentCategory(category)
            
        case "intentType":
            guard let str = value?.stringValue else {
                throw PolicySchemaError.invalidValue("intentType requires string value")
            }
            return .intentType(str)
            
        case "scopeType":
            guard let str = value?.stringValue,
                  let scope = ScopeType(rawValue: str) else {
                throw PolicySchemaError.invalidValue("scopeType requires valid scope string")
            }
            return .scopeType(scope)
            
        case "confidenceAbove":
            guard let num = value?.doubleValue else {
                throw PolicySchemaError.invalidValue("confidenceAbove requires number value")
            }
            return .confidenceAbove(num)
            
        case "confidenceBelow":
            guard let num = value?.doubleValue else {
                throw PolicySchemaError.invalidValue("confidenceBelow requires number value")
            }
            return .confidenceBelow(num)
            
        case "filePattern":
            guard let str = value?.stringValue else {
                throw PolicySchemaError.invalidValue("filePattern requires string value")
            }
            return .filePattern(str)
            
        case "maxSteps":
            guard let num = value?.intValue ?? value?.doubleValue.map({ Int($0) }) else {
                throw PolicySchemaError.invalidValue("maxSteps requires integer value")
            }
            return .maxSteps(num)
            
        case "all":
            guard let subs = conditions else {
                throw PolicySchemaError.invalidValue("all requires conditions array")
            }
            return .all(try subs.map { try $0.toCondition() })
            
        case "any":
            guard let subs = conditions else {
                throw PolicySchemaError.invalidValue("any requires conditions array")
            }
            return .any(try subs.map { try $0.toCondition() })
            
        case "not":
            guard let subs = conditions, let first = subs.first else {
                throw PolicySchemaError.invalidValue("not requires one condition")
            }
            return .not(try first.toCondition())
            
        default:
            throw PolicySchemaError.unknownConditionType(type)
        }
    }
}

// MARK: - Schema Errors

public enum PolicySchemaError: Error, LocalizedError {
    case invalidDecision(String)
    case invalidValue(String)
    case unknownConditionType(String)
    case fileNotFound(String)
    case parseError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidDecision(let d): return "Invalid decision: \(d)"
        case .invalidValue(let v): return "Invalid value: \(v)"
        case .unknownConditionType(let t): return "Unknown condition type: \(t)"
        case .fileNotFound(let p): return "Policy file not found: \(p)"
        case .parseError(let e): return "Policy parse error: \(e)"
        }
    }
}

// MARK: - Policy Loading

extension ApprovalPolicy {
    
    /// Load policy from JSON file
    public static func load(from path: String) throws -> ApprovalPolicy {
        guard FileManager.default.fileExists(atPath: path) else {
            throw PolicySchemaError.fileNotFound(path)
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let schema = try JSONDecoder().decode(PolicySchema.self, from: data)
        return try schema.toPolicy()
    }
    
    /// Load policy by name (built-in) or path (custom)
    public static func resolve(_ nameOrPath: String) throws -> ApprovalPolicy {
        // Check built-in policies first
        switch nameOrPath.lowercased() {
        case "conservative": return .conservative
        case "moderate": return .moderate
        case "permissive": return .permissive
        case "ci": return .ci
        case "strict": return .strict
        default:
            // Try loading as file path
            return try load(from: nameOrPath)
        }
    }
    
    /// Export policy to JSON
    public func toJSON(prettyPrint: Bool = true) throws -> Data {
        let schema = toSchema()
        let encoder = JSONEncoder()
        if prettyPrint {
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        }
        return try encoder.encode(schema)
    }
    
    /// Convert to schema for serialization
    public func toSchema() -> PolicySchema {
        PolicySchema(
            name: name,
            description: description.isEmpty ? nil : description,
            version: "1.0",
            rules: rules.map { $0.toSchema() },
            defaultDecision: defaultDecision.rawValue
        )
    }
}

extension PolicyRule {
    func toSchema() -> RuleSchema {
        RuleSchema(
            condition: condition.toSchema(),
            decision: decision.rawValue,
            reason: reason
        )
    }
}

extension PolicyCondition {
    func toSchema() -> ConditionSchema {
        switch self {
        case .intentCategory(let cat):
            return ConditionSchema(type: "intentCategory", value: .string(cat.rawValue))
        case .intentType(let t):
            return ConditionSchema(type: "intentType", value: .string(t))
        case .scopeType(let s):
            return ConditionSchema(type: "scopeType", value: .string(s.rawValue))
        case .confidenceAbove(let n):
            return ConditionSchema(type: "confidenceAbove", value: .number(n))
        case .confidenceBelow(let n):
            return ConditionSchema(type: "confidenceBelow", value: .number(n))
        case .filePattern(let p):
            return ConditionSchema(type: "filePattern", value: .string(p))
        case .maxSteps(let n):
            return ConditionSchema(type: "maxSteps", value: .integer(n))
        case .all(let conds):
            return ConditionSchema(type: "all", value: nil, conditions: conds.map { $0.toSchema() })
        case .any(let conds):
            return ConditionSchema(type: "any", value: nil, conditions: conds.map { $0.toSchema() })
        case .not(let cond):
            return ConditionSchema(type: "not", value: nil, conditions: [cond.toSchema()])
        }
    }
}

// MARK: - IntentCategory Raw Value

extension IntentCategory: RawRepresentable {
    public init?(rawValue: String) {
        switch rawValue {
        case "structural": self = .structural
        case "dataFlow": self = .dataFlow
        case "quality": self = .quality
        case "architecture": self = .architecture
        case "documentation": self = .documentation
        default: return nil
        }
    }
    
    public var rawValue: String {
        switch self {
        case .structural: return "structural"
        case .dataFlow: return "dataFlow"
        case .quality: return "quality"
        case .architecture: return "architecture"
        case .documentation: return "documentation"
        }
    }
}
