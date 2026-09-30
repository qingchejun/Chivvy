import SwiftUI

@main
struct TickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Tick", id: "main") {
            LanguageRoot { ContentView() }
        }
        .defaultSize(width: 380, height: 490)
    }
}
