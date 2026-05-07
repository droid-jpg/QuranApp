import SwiftUI

@main
struct QuranAppApp: App {
    @StateObject private var audioService = AudioService()

    var body: some Scene {
        WindowGroup {
            SurahListView()
                .environmentObject(audioService)
        }
    }
}
