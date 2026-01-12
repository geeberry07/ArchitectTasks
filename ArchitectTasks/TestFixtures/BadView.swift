import SwiftUI

// This file intentionally has issues for the analyzer to find

class ProfileViewModel: ObservableObject {
    @Published var name: String = ""
}

struct ProfileView: View {
    // ⚠️ Missing @StateObject or @ObservedObject
    var viewModel: ProfileViewModel
    
    var body: some View {
        Text(viewModel.name)
    }
}

struct SettingsView: View {
    // ⚠️ Missing @StateObject
    var settingsStore: SettingsStore
    
    var body: some View {
        Text("Settings")
    }
}

class SettingsStore: ObservableObject {
    @Published var darkMode: Bool = false
}
