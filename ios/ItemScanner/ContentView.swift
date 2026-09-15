import SwiftUI

struct ContentView: View {
    @StateObject private var store = WebViewStore()

    // The deployed web app. Update if the GitHub Pages URL ever changes.
    private let appURL = URL(string: "https://sdgardner.github.io/furniture-scanner/")!

    var body: some View {
        WebView(store: store, url: appURL)
            .ignoresSafeArea()
            .fullScreenCover(isPresented: $store.showMeasure) {
                ARMeasureScreen { result in
                    store.showMeasure = false
                    if let r = result {
                        store.sendResult(r)
                    } else {
                        store.sendCancel()
                    }
                }
                .ignoresSafeArea()
            }
    }
}
