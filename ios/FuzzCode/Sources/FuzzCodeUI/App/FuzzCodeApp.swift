import SwiftUI
import FuzzCodeCore

@main
public struct FuzzCodeApp: App {
    public init() {
        configureAppearance()
        seedDefaultProvidersIfFirstLaunch()
    }
    
    public var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
    
    private func configureAppearance() {
        // Customize native iOS navigation and tab bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor(red: 11/255, green: 12/255, blue: 14/255, alpha: 1.0)
        navBarAppearance.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .bold)
        ]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor(red: 14/255, green: 16/255, blue: 20/255, alpha: 1.0)
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }
    
    private func seedDefaultProvidersIfFirstLaunch() {
        let existing = StorageService.shared.loadProviders()
        if existing.isEmpty {
            let defaultProvider = ProviderConfig(
                displayName: "Kilo / OpenAI Compatible",
                baseURLString: "https://api.openai.com/v1",
                selectedModel: "gpt-4o"
            )
            StorageService.shared.saveProviders([defaultProvider])
        }
    }
}

public struct MainTabView: View {
    @State private var selectedTab = 0
    
    public init() {}
    
    public var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(1)
            
            AgentsView()
                .tabItem {
                    Label("Agents", systemImage: "terminal.fill")
                }
                .tag(2)
            
            ProvidersView()
                .tabItem {
                    Label("Providers", systemImage: "slider.horizontal.3")
                }
                .tag(3)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(4)
        }
        .tint(FuzzTheme.acidGreen)
    }
}
