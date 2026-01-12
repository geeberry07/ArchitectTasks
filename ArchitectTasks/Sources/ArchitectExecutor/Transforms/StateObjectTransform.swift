import Foundation
import ArchitectCore

// MARK: - Deterministic Transform Protocol

/// A fully deterministic code transformation.
/// No LLMs, no heuristics - pure syntax rewriting.
public protocol DeterministicTransform: Sendable {
    /// The intent types this transform handles
    var supportedIntents: [String] { get }
    
    /// Apply the transform to source code
    func apply(to source: String, intent: TaskIntent, context: TransformContext) throws -> TransformResult
}

// MARK: - Transform Context

public struct TransformContext: Sendable {
    public var filePath: String
    public var propertyName: String?
    public var typeName: String?
    public var lineNumber: Int?
    
    public init(
        filePath: String,
        propertyName: String? = nil,
        typeName: String? = nil,
        lineNumber: Int? = nil
    ) {
        self.filePath = filePath
        self.propertyName = propertyName
        self.typeName = typeName
        self.lineNumber = lineNumber
    }
}

// MARK: - Transform Result

public struct TransformResult: Sendable {
    public var originalSource: String
    public var transformedSource: String
    public var diff: String
    public var linesChanged: Int
    public var warnings: [String]
    
    public init(
        originalSource: String,
        transformedSource: String,
        diff: String,
        linesChanged: Int,
        warnings: [String] = []
    ) {
        self.originalSource = originalSource
        self.transformedSource = transformedSource
        self.diff = diff
        self.linesChanged = linesChanged
        self.warnings = warnings
    }
    
    public var hasChanges: Bool {
        originalSource != transformedSource
    }
}

// MARK: - Transform Errors

public enum TransformError: Error, Sendable {
    case propertyNotFound(String)
    case alreadyHasWrapper(String)
    case parseError(String)
    case unsupportedIntent(String)
    case multipleMatches(String, count: Int)
}

// MARK: - StateObject Transform (Deterministic)

/// Adds @StateObject or @ObservedObject wrapper to a property.
/// Fully deterministic - uses regex-based transformation.
public struct StateObjectTransform: DeterministicTransform, Sendable {
    
    public var supportedIntents: [String] {
        ["addStateObject", "addObservedObject"]
    }
    
    public init() {}
    
    public func apply(
        to source: String,
        intent: TaskIntent,
        context: TransformContext
    ) throws -> TransformResult {
        
        guard case .addStateObject(let property, let type, _) = intent else {
            throw TransformError.unsupportedIntent(String(describing: intent))
        }
        
        let lines = source.components(separatedBy: "\n")
        var modifiedLines = lines
        var changedLineIndex: Int?
        var originalLine: String?
        var newLine: String?
        
        // Find the property declaration
        let propertyPattern = try NSRegularExpression(
            pattern: #"^(\s*)(var|let)\s+\#(property)\s*:\s*\#(type)"#
                .replacingOccurrences(of: "#(property)", with: NSRegularExpression.escapedPattern(for: property))
                .replacingOccurrences(of: "#(type)", with: NSRegularExpression.escapedPattern(for: type)),
            options: []
        )
        
        var matchCount = 0
        
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            
            // Skip if already has a wrapper
            if line.contains("@StateObject") || 
               line.contains("@ObservedObject") ||
               line.contains("@State") ||
               line.contains("@Binding") ||
               line.contains("@Environment") {
                if line.contains(property) {
                    throw TransformError.alreadyHasWrapper(property)
                }
                continue
            }
            
            if propertyPattern.firstMatch(in: line, options: [], range: range) != nil {
                matchCount += 1
                changedLineIndex = index
                originalLine = line
                
                // Determine wrapper type based on context
                let wrapper = determineWrapper(type: type)
                
                // Insert the wrapper
                if let match = propertyPattern.firstMatch(in: line, options: [], range: range),
                   let indentRange = Range(match.range(at: 1), in: line) {
                    let indent = String(line[indentRange])
                    newLine = "\(indent)\(wrapper) var \(property): \(type)"
                    
                    // Preserve any trailing content (= initializer, etc.)
                    if let varRange = line.range(of: "var \(property): \(type)") {
                        let trailing = String(line[varRange.upperBound...])
                        newLine = "\(indent)\(wrapper) var \(property): \(type)\(trailing)"
                    }
                }
            }
        }
        
        guard matchCount > 0 else {
            throw TransformError.propertyNotFound(property)
        }
        
        guard matchCount == 1 else {
            throw TransformError.multipleMatches(property, count: matchCount)
        }
        
        guard let lineIndex = changedLineIndex,
              let original = originalLine,
              let modified = newLine else {
            throw TransformError.propertyNotFound(property)
        }
        
        modifiedLines[lineIndex] = modified
        
        let transformedSource = modifiedLines.joined(separator: "\n")
        let diff = generateDiff(
            filePath: context.filePath,
            lineNumber: lineIndex + 1,
            original: original,
            modified: modified
        )
        
        return TransformResult(
            originalSource: source,
            transformedSource: transformedSource,
            diff: diff,
            linesChanged: 1
        )
    }
    
    // MARK: - Private
    
    private func determineWrapper(type: String) -> String {
        // Heuristic: if type ends with "ViewModel" or is created locally, use @StateObject
        // Otherwise use @ObservedObject (passed in from parent)
        if type.hasSuffix("ViewModel") || type.hasSuffix("Store") {
            return "@StateObject"
        }
        return "@ObservedObject"
    }
    
    private func generateDiff(
        filePath: String,
        lineNumber: Int,
        original: String,
        modified: String
    ) -> String {
        """
        --- a/\(filePath)
        +++ b/\(filePath)
        @@ -\(lineNumber),1 +\(lineNumber),1 @@
        -\(original)
        +\(modified)
        """
    }
}

// MARK: - Transform Registry

/// Registry of all available deterministic transforms.
public final class TransformRegistry: @unchecked Sendable {
    public static let shared = TransformRegistry()
    
    private var transforms: [String: DeterministicTransform] = [:]
    
    private init() {
        // Register built-in transforms
        register(StateObjectTransform())
    }
    
    public func register(_ transform: DeterministicTransform) {
        for intent in transform.supportedIntents {
            transforms[intent] = transform
        }
    }
    
    public func transform(for intent: TaskIntent) -> DeterministicTransform? {
        let intentName = String(describing: intent).components(separatedBy: "(").first ?? ""
        return transforms[intentName]
    }
    
    public var availableTransforms: [String] {
        Array(transforms.keys)
    }
}
