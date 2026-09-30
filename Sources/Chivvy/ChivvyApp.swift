import SwiftUI

@main
struct ChivvyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Chivvy", id: "main") {
            LanguageRoot { ContentView() }
        }
        .defaultSize(width: 380, height: 490)
    }
}
