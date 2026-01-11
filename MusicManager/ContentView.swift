import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject var manager = DeviceManager.shared
    @State private var status = "Ready"
    @State private var songs: [SongMetadata] = []
    @State private var isInjecting = false
    @State private var selectedTab = 0
    @State private var hasCompletedOnboarding = false
    @State private var showSplash = true
    
    var body: some View {
        ZStack {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
            
            if !showSplash {
                Group {
            if hasCompletedOnboarding {
                // Main App
                ZStack(alignment: .bottom) {
                    // Background that extends to edges
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()
                    
                    Group {
                        if selectedTab == 0 {
                            MusicView(
                                manager: manager,
                                songs: $songs,
                                isInjecting: $isInjecting,
                                status: $status
                            )
                        } else {
                            SettingsView(
                                manager: manager,
                                status: $status
                            )
                        }
                    }
                    .padding(.bottom, 80)
                    
                    FloatingTabBar(selectedTab: $selectedTab)
                        .padding(.bottom, 20)
                }
                .ignoresSafeArea(.keyboard)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.8)),
                    removal: .opacity.combined(with: .scale(scale: 1.2))
                ))
            } else {
                // Onboarding
                OnboardingView(
                    manager: manager,
                    isComplete: $hasCompletedOnboarding
                )
            }
                }
            }
        }
        .onAppear {
            // Splash Screen Timer
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
            }
            
            // Check if pairing file already exists
            if FileManager.default.fileExists(atPath: manager.pairingFile.path) {
                hasCompletedOnboarding = true
                status = "Found pairing file, connecting..."
                manager.startHeartbeat { err in
                    DispatchQueue.main.async {
                        if err == IdeviceSuccess {
                            self.status = "Connected!"
                        } else {
                            self.status = "Connection failed"
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Floating Tab Bar

struct FloatingTabBar: View {
    @Binding var selectedTab: Int
    
    var body: some View {
        HStack(spacing: 0) {
            // Music Tab
            TabBarButton(
                icon: "music.note",
                title: "Music",
                isSelected: selectedTab == 0
            ) {
                selectedTab = 0
            }
            
            // Settings Tab
            TabBarButton(
                icon: "gearshape.fill",
                title: "Settings",
                isSelected: selectedTab == 1
            ) {
                selectedTab = 1
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(.systemBackground))
        )
        .overlay(
            Capsule()
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}

struct TabBarButton: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(isSelected ? .blue : .gray)
            .frame(width: 70, height: 50)
            .background(
                isSelected ?
                    Capsule().fill(Color.blue.opacity(0.1)) :
                    Capsule().fill(Color.clear)
            )
        }
    }
}

// MARK: - UIKit Document Picker Wrapper

struct DocumentPicker: UIViewControllerRepresentable {
    let types: [UTType]
    var allowsMultiple: Bool = false
    let completion: ([URL]?) -> Void
    
    init(types: [UTType], allowsMultiple: Bool = false, completion: @escaping ([URL]?) -> Void) {
        self.types = types
        self.allowsMultiple = allowsMultiple
        self.completion = completion
    }
    
    init(types: [UTType], completion: @escaping (URL?) -> Void) {
        self.types = types
        self.allowsMultiple = false
        self.completion = { urls in
            completion(urls?.first)
        }
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = allowsMultiple
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let completion: ([URL]?) -> Void
        
        init(completion: @escaping ([URL]?) -> Void) {
            self.completion = completion
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            completion(urls)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            completion(nil)
        }
    }
}

#Preview {
    ContentView()
}
