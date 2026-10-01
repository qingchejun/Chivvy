import SwiftUI

@main
struct ChivvyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Chivvy", id: "main") {
            LanguageRoot { MainView() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 640, height: 460)
    }
}
