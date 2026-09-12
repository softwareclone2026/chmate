import SwiftUI
import WebKit

struct WebSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            WebView(url: url).ignoresSafeArea(edges: .bottom)
                .navigationTitle(url.host ?? "ブラウザ").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("閉じる") { dismiss() } }
        }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(); view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url)); return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct ImageSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(.white) }.padding()
        }
    }
}
