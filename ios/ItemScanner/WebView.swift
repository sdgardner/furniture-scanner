import SwiftUI
import WebKit

/// Hosts the Item Scanner web app and bridges messages between JS and native.
/// JS calls window.webkit.messageHandlers.arMeasure.postMessage({}) to open
/// the AR measure screen; results return via window.__arMeasureResult({...}).
final class WebViewStore: NSObject, ObservableObject, WKScriptMessageHandler {
    @Published var showMeasure = false
    weak var webView: WKWebView?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "arMeasure" {
            DispatchQueue.main.async { self.showMeasure = true }
        }
    }

    func sendResult(_ r: ARMeasureResult) {
        let w = r.width.map(String.init) ?? "null"
        let h = r.height.map(String.init) ?? "null"
        let d = r.depth.map(String.init) ?? "null"
        let js = "window.__arMeasureResult && window.__arMeasureResult({width:\(w),height:\(h),depth:\(d)});"
        webView?.evaluateJavaScript(js)
    }

    func sendCancel() {
        webView?.evaluateJavaScript("window.__arMeasureCancel && window.__arMeasureCancel();")
    }
}

struct WebView: UIViewRepresentable {
    let store: WebViewStore
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Let the web app's camera capture (photos + walkthrough video) work in-app
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(store, name: "arMeasure")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false
        webView.backgroundColor = .black
        store.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
