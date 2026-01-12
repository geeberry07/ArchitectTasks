import XCTest
@testable import ArchitectCore
@testable import ArchitectExecutor

final class StateObjectTransformTests: XCTestCase {
    
    let transform = StateObjectTransform()
    
    func testAddStateObjectToProperty() throws {
        let source = """
        import SwiftUI
        
        struct ProfileView: View {
            var viewModel: ProfileViewModel
            
            var body: some View {
                Text(viewModel.name)
            }
        }
        """
        
        let intent = TaskIntent.addStateObject(
            property: "viewModel",
            type: "ProfileViewModel",
            in: "ProfileView.swift"
        )
        
        let context = TransformContext(
            filePath: "ProfileView.swift",
            propertyName: "viewModel",
            typeName: "ProfileViewModel"
        )
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        XCTAssertTrue(result.hasChanges)
        XCTAssertTrue(result.transformedSource.contains("@StateObject var viewModel"))
        XCTAssertEqual(result.linesChanged, 1)
        XCTAssertTrue(result.diff.contains("-    var viewModel: ProfileViewModel"))
        XCTAssertTrue(result.diff.contains("+    @StateObject var viewModel: ProfileViewModel"))
    }
    
    func testAddObservedObjectToModel() throws {
        let source = """
        struct ChildView: View {
            var model: DataModel
            
            var body: some View {
                Text("Hello")
            }
        }
        """
        
        let intent = TaskIntent.addStateObject(
            property: "model",
            type: "DataModel",
            in: "ChildView.swift"
        )
        
        let context = TransformContext(
            filePath: "ChildView.swift",
            propertyName: "model",
            typeName: "DataModel"
        )
        
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        // DataModel doesn't end with ViewModel/Store, so should use @ObservedObject
        XCTAssertTrue(result.transformedSource.contains("@ObservedObject var model"))
    }
    
    func testThrowsWhenPropertyNotFound() {
        let source = """
        struct View: View {
            var other: String
        }
        """
        
        let intent = TaskIntent.addStateObject(
            property: "viewModel",
            type: "ViewModel",
            in: "View.swift"
        )
        
        let context = TransformContext(filePath: "View.swift")
        
        XCTAssertThrowsError(try transform.apply(to: source, intent: intent, context: context)) { error in
            guard case TransformError.propertyNotFound = error else {
                XCTFail("Expected propertyNotFound error")
                return
            }
        }
    }
    
    func testThrowsWhenAlreadyHasWrapper() {
        let source = """
        struct View: View {
            @StateObject var viewModel: ViewModel
        }
        """
        
        let intent = TaskIntent.addStateObject(
            property: "viewModel",
            type: "ViewModel",
            in: "View.swift"
        )
        
        let context = TransformContext(filePath: "View.swift")
        
        XCTAssertThrowsError(try transform.apply(to: source, intent: intent, context: context)) { error in
            guard case TransformError.alreadyHasWrapper = error else {
                XCTFail("Expected alreadyHasWrapper error")
                return
            }
        }
    }
    
    func testPreservesIndentation() throws {
        let source = """
        struct View: View {
                var viewModel: ViewModel
        }
        """
        
        let intent = TaskIntent.addStateObject(
            property: "viewModel",
            type: "ViewModel",
            in: "View.swift"
        )
        
        let context = TransformContext(filePath: "View.swift")
        let result = try transform.apply(to: source, intent: intent, context: context)
        
        // Should preserve the 8-space indentation
        XCTAssertTrue(result.transformedSource.contains("        @StateObject var viewModel"))
    }
    
    func testTransformRegistry() {
        let registry = TransformRegistry.shared
        
        let intent = TaskIntent.addStateObject(
            property: "vm",
            type: "VM",
            in: "File.swift"
        )
        
        let transform = registry.transform(for: intent)
        XCTAssertNotNil(transform)
        XCTAssertTrue(transform?.supportedIntents.contains("addStateObject") ?? false)
    }
    
    func testDeterministicExecutor() throws {
        let executor = DeterministicExecutor()
        
        let source = """
        struct View: View {
            var viewModel: ViewModel
        }
        """
        
        let intent = TaskIntent.addStateObject(
            property: "viewModel",
            type: "ViewModel",
            in: "View.swift"
        )
        
        let context = TransformContext(filePath: "View.swift")
        
        let result = try executor.executeTransform(intent: intent, source: source, context: context)
        
        XCTAssertTrue(result.hasChanges)
        XCTAssertTrue(result.transformedSource.contains("@StateObject"))
    }
}
