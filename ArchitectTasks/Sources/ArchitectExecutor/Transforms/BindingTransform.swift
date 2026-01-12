import Foundation
import ArchitectCore

// MARK: - Binding Transform (Deterministic)

/// Adds @Binding wrapper to a property.
/// Fully deterministic - uses regex-based transformation.
public struct BindingTransform: DeterministicTransform, Sendable {
    
    public var supportedIntents: [String] {
        ["addBinding"]
    }
    
    public init() {}
    
    public func apply(
        to source: String,
        intent: TaskIntent,
        context: TransformContext
    ) throws -> TransformResult {
        
        guard case .addBinding(let property, _) = intent else {
            throw TransformError.unsupportedIntent(String(describing: intent))
        }
        
        let lines = source.components(separatedBy: "\n")
        var modifiedLines = lines
        var changedLineIndex: Int?
        var originalLine: String?
        var newLine: String?
        
        // Pattern: var propertyName: Type (with optional initializer)
        // Captures: indent, var/let, property name, type
        let propertyPattern = try NSRegularExpression(
            pattern: #"^(\s*)(var|let)\s+(\#(NSRegularExpression.escapedPattern(for: property)))\s*:\s*(\w+)"#,
            options: []
        )
        
        var matchCount = 0
        
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            
            // Skip if already has a wrapper
            if line.contains("@Binding") ||
               line.contains("@State") ||
               line.contains("@StateObject") ||
               line.contains("@ObservedObject") ||
               line.contains("@Environment") {
                if line.contains(property) {
                    throw TransformError.alreadyHasWrapper(property)
                }
                continue
            }
            
            if let match = propertyPattern.firstMatch(in: line, options: [], range: range) {
                matchCount += 1
                changedLineIndex = index
                originalLine = line
                
                // Extract components
                guard let indentRange = Range(match.range(at: 1), in: line),
                      let typeRange = Range(match.range(at: 4), in: line) else {
                    continue
                }
                
                let indent = String(line[indentRange])
                let type = String(line[typeRange])
                
                // Build new line with @Binding
                // @Binding requires var, not let
                newLine = "\(indent)@Binding var \(property): \(type)"
                
                // Preserve trailing content (but remove initializer - @Binding can't have one)
                // Check if there's a trailing comment
                if let commentRange = line.range(of: "//") {
                    let comment = String(line[commentRange.lowerBound...])
                    newLine = "\(indent)@Binding var \(property): \(type) \(comment)"
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

// MARK: - Import Transform (Deterministic)

/// Adds an import statement if not present.
public struct ImportTransform: DeterministicTransform, Sendable {
    
    public var supportedIntents: [String] {
        ["addImport"]
    }
    
    public init() {}
    
    public func apply(
        to source: String,
        intent: TaskIntent,
        context: TransformContext
    ) throws -> TransformResult {
        
        // Extract module name from context
        guard let moduleName = context.typeName else {
            throw TransformError.unsupportedIntent("addImport requires module name in context")
        }
        
        let importStatement = "import \(moduleName)"
        
        // Check if already imported
        if source.contains(importStatement) {
            return TransformResult(
                originalSource: source,
                transformedSource: source,
                diff: "// Already imported: \(moduleName)",
                linesChanged: 0,
                warnings: ["Module '\(moduleName)' is already imported"]
            )
        }
        
        let lines = source.components(separatedBy: "\n")
        var modifiedLines = lines
        
        // Find the right place to insert (after existing imports, or at top)
        var insertIndex = 0
        for (index, line) in lines.enumerated() {
            if line.hasPrefix("import ") {
                insertIndex = index + 1
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty && 
                      !line.hasPrefix("//") && 
                      !line.hasPrefix("import ") {
                // Found first non-import, non-comment, non-empty line
                break
            }
        }
        
        modifiedLines.insert(importStatement, at: insertIndex)
        
        let transformedSource = modifiedLines.joined(separator: "\n")
        let diff = """
        --- a/\(context.filePath)
        +++ b/\(context.filePath)
        @@ -\(insertIndex),0 +\(insertIndex + 1),1 @@
        +\(importStatement)
        """
        
        return TransformResult(
            originalSource: source,
            transformedSource: transformedSource,
            diff: diff,
            linesChanged: 1
        )
    }
}

// MARK: - Register Additional Transforms

extension TransformRegistry {
    
    /// Register all built-in transforms
    public func registerBuiltins() {
        register(StateObjectTransform())
        register(BindingTransform())
        register(ImportTransform())
    }
}
