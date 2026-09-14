// Fotografa una pagina HTML locale con WebKit, per guardarla senza un browser.
//
// Perché esiste: il pannello del browser di Claude Code non fotografa i file locali,
// e su questo Mac non c'è un browser senza testa. WebKit sì.
//
//   swiftc -O scripts/render-html.swift -o /tmp/render-html
//   /tmp/render-html "$PWD/docs/design/quattro-facce-per-cruisy.html" /tmp/pagina.jpg
//
// Aspetta quattro secondi per i caratteri di Google Fonts, poi fotografa la pagina
// intera. Senza `<meta charset="utf-8">` in testa le lettere accentate escono sbagliate.
import AppKit
import WebKit

final class Grabber: NSObject, WKNavigationDelegate {
    let web: WKWebView
    let out: String
    init(file: String, out: String, width: CGFloat) {
        let config = WKWebViewConfiguration()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: 900), configuration: config)
        self.out = out
        super.init()
        web.navigationDelegate = self
        let url = URL(fileURLWithPath: file)
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Il tempo di scaricare i caratteri di Google Fonts.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { value, _ in
                let h = (value as? CGFloat) ?? 4000
                webView.frame = NSRect(x: 0, y: 0, width: webView.frame.width, height: h)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    let conf = WKSnapshotConfiguration()
                    conf.rect = NSRect(x: 0, y: 0, width: webView.frame.width, height: h)
                    webView.takeSnapshot(with: conf) { image, error in
                        guard let image, let tiff = image.tiffRepresentation,
                              let rep = NSBitmapImageRep(data: tiff),
                              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                            print("errore:", error as Any); exit(1)
                        }
                        try? data.write(to: URL(fileURLWithPath: self.out))
                        print("scritto", self.out, Int(h))
                        exit(0)
                    }
                }
            }
        }
    }
}

let app = NSApplication.shared
let grabber = Grabber(file: CommandLine.arguments[1], out: CommandLine.arguments[2], width: 1280)
_ = grabber
app.run()
