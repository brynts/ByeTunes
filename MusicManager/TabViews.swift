import SwiftUI

// MARK: - Legacy Tab Bar (Custom Floating Bar)
struct LegacyTabBarView: View {
    @ObservedObject var manager: DeviceManager
    @Binding var songs: [SongMetadata]
    @Binding var ringtones: [RingtoneMetadata]
    @Binding var isInjecting: Bool
    @Binding var status: String
    @Binding var selectedTab: Int
    @Binding var showingLogViewer: Bool
    
    var body: some View {
        ZStack(alignment: .bottom) {
            
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
                } else if selectedTab == 1 {
                    RingtonesView(manager: manager, ringtones: $ringtones)
                } else {
                    SettingsView(
                        manager: manager,
                        status: $status
                    )
                }
            }
            .safeAreaInset(edge: .bottom) {
                 Color.clear.frame(height: 80)
            }
            .overlay(alignment: .bottom) {
                FloatingTabBar(selectedTab: $selectedTab)
                    .padding(.bottom, 0)
            }
        }
        .sheet(isPresented: $showingLogViewer) {
            LogViewer()
        }
        .ignoresSafeArea(.keyboard)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.8)),
            removal: .opacity.combined(with: .scale(scale: 1.2))
        ))
    }
}

// MARK: - Modern Tab View (Standard TabBar for iOS 26+)
struct ModernTabView: View {
    @ObservedObject var manager: DeviceManager
    @Binding var songs: [SongMetadata]
    @Binding var ringtones: [RingtoneMetadata]
    @Binding var isInjecting: Bool
    @Binding var status: String
    @Binding var selectedTab: Int
    @Binding var showingLogViewer: Bool
    
    var body: some View {
        TabView(selection: $selectedTab) {
            MusicView(
                manager: manager,
                songs: $songs,
                isInjecting: $isInjecting,
                status: $status
            )
            .tabItem {
                Label("Music", systemImage: "music.note")
            }
            .tag(0)
            
            RingtonesView(manager: manager, ringtones: $ringtones)
            .tabItem {
                Label("Ringtones", systemImage: "bell.badge.fill")
            }
            .tag(1)
            
            SettingsView(manager: manager, status: $status)
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        .sheet(isPresented: $showingLogViewer) {
            LogViewer()
        }
    }
}
