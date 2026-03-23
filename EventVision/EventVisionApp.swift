import SwiftUI

@main
struct EventVisionApp: App {
    @StateObject private var scanStore = ScanStore()
    @StateObject private var assetStore = AssetStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(scanStore)
                .environmentObject(assetStore)
        }
    }
}
