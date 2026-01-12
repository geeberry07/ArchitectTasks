import Foundation

/// Represents a location in source code
public struct SourceLocation: Codable, Hashable, Sendable {
    public var file: String
    public var line: Int
    public var column: Int
    
    public init(file: String, line: Int = 0, column: Int = 0) {
        self.file = file
        self.line = line
        self.column = column
    }
    
    public var description: String {
        "\(file):\(line):\(column)"
    }
}
