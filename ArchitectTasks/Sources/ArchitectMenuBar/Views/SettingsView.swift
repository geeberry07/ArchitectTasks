import SwiftUI
import ArchitectCore
import ArchitectHost

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("autoAnalyzeOnSave") private var autoAnalyzeOnSave = false
    @AppStorage("showNotifications") private var showNotifications = true
    @AppStorage("defaultPolicy") private var defaultPolicy = "moderate"
    
    var body: some View {
        TabView {
            GeneralSettingsView(
                autoAnalyzeOnSave: $autoAnalyzeOnSave,
                showNotifications: $showNotifications,
                defaultPolicy: $defaultPolicy
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
            AnalysisSettingsView()
            .tabItem {
                Label("Analysis", systemImage: "magnifyingglass")
            }
            
            PolicySettingsView()
            .tabItem {
                Label("Policies", systemImage: "shield")
            }
            
            AboutView()
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

private struct GeneralSettingsView: View {
    @Binding var autoAnalyzeOnSave: Bool
    @Binding var showNotifications: Bool
    @Binding var defaultPolicy: String
    
    var body: some View {
        Form {
            Section {
                Toggle("Auto-analyze on file save", isOn: $autoAnalyzeOnSave)
                Toggle("Show notifications", isOn: $showNotifications)
            }
            
            Section {
                Picker("Default Policy", selection: $defaultPolicy) {
                    Text("Conservative").tag("conservative")
                    Text("Moderate").tag("moderate")
                    Text("Permissive").tag("permissive")
                    Text("Strict").tag("strict")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Analysis Settings

private struct AnalysisSettingsView: View {
    @AppStorage("maxFunctionLines") private var maxFunctionLines = 50
    @AppStorage("maxParameters") private var maxParameters = 5
    @AppStorage("maxNestingDepth") private var maxNestingDepth = 4
    @AppStorage("maxFileLines") private var maxFileLines = 500
    
    var body: some View {
        Form {
            Section("Complexity Thresholds") {
                Stepper("Max function lines: \(maxFunctionLines)", value: $maxFunctionLines, in: 20...200, step: 10)
                Stepper("Max parameters: \(maxParameters)", value: $maxParameters, in: 2...10)
                Stepper("Max nesting depth: \(maxNestingDepth)", value: $maxNestingDepth, in: 2...8)
                Stepper("Max file lines: \(maxFileLines)", value: $maxFileLines, in: 100...1000, step: 50)
            }
            
            Section {
                Button("Reset to Defaults") {
                    maxFunctionLines = 50
                    maxParameters = 5
                    maxNestingDepth = 4
                    maxFileLines = 500
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Policy Settings

private struct PolicySettingsView: View {
    @State private var customPolicyPath: String = ""
    
    var body: some View {
        Form {
            Section("Built-in Policies") {
                PolicyRow(name: "Conservative", description: "Only auto-approve documentation")
                PolicyRow(name: "Moderate", description: "Auto-approve high-confidence, single-file")
                PolicyRow(name: "Permissive", description: "Auto-approve most, deny architecture")
                PolicyRow(name: "Strict", description: "Require human approval for everything")
            }
            
            Section("Custom Policy") {
                HStack {
                    TextField("Policy JSON path", text: $customPolicyPath)
                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.json]
                        if panel.runModal() == .OK, let url = panel.url {
                            customPolicyPath = url.path
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct PolicyRow: View {
    let name: String
    let description: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(name)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Export") {
                exportPolicy(name: name.lowercased())
            }
            .buttonStyle(.borderless)
        }
    }
    
    private func exportPolicy(name: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(name)-policy.json"
        
        if panel.runModal() == .OK, let url = panel.url {
            if let policy = try? ApprovalPolicy.resolve(name),
               let json = try? policy.toJSON() {
                try? json.write(to: url)
            }
        }
    }
}

// MARK: - About View

private struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)
            
            Text("ArchitectTasks")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Version 0.1.0")
                .foregroundColor(.secondary)
            
            Text("Task-driven code intelligence")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
                .frame(width: 200)
            
            Link("GitHub Repository", destination: URL(string: "https://github.com/yourorg/ArchitectTasks")!)
            
            Text("MIT License")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
