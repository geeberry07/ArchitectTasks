import Foundation

// Get project root from arguments or current directory
let projectRoot: URL
if CommandLine.arguments.count > 1 {
    projectRoot = URL(fileURLWithPath: CommandLine.arguments[1])
} else {
    projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
}

// Run the language server
Task {
    await runLanguageServer(projectRoot: projectRoot)
}

// Keep the process running
RunLoop.main.run()
