import AppKit
import WebKit
// Renders an SVG (or HTML) file to PNG at its own size with WebKit: what a browser shows.
let args = CommandLine.arguments
let src = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let w = Double(args[3])!, h = Double(args[4])!
let app = NSApplication.shared
let web = WKWebView(frame: NSRect(x: 0, y: 0, width: w, height: h))
final class D: NSObject, WKNavigationDelegate {
    func webView(_ v: WKWebView, didFinish n: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            let c = WKSnapshotConfiguration(); c.rect = NSRect(x: 0, y: 0, width: w, height: h)
            v.takeSnapshot(with: c) { img, _ in
                let rep = NSBitmapImageRep(data: img!.tiffRepresentation!)!
                try! rep.representation(using: .png, properties: [:])!.write(to: out); exit(0)
            }
        }
    }
}
let d = D(); web.navigationDelegate = d
web.setValue(false, forKey: "drawsBackground")
let svg = try! String(contentsOf: src, encoding: .utf8)
let html = "<html><body style='margin:0;background:transparent;color:#fff'><div style='width:\(Int(w))px;height:\(Int(h))px'>\(svg)</div><style>svg{width:100%;height:100%;display:block}</style></body></html>"
web.loadHTMLString(html, baseURL: nil)
app.run()
