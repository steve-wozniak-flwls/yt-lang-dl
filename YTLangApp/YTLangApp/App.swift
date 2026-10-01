import SwiftUI

@main
struct YTLangApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 520, minHeight: 480)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 520, height: 540)
    }
}
