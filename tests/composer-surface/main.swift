import AppKit
import WebKit

// An offline fixture of Codex's home and thread surface ownership, without app data.
final class ComposerSurfaceProbe: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let css: String
    let screenshot: String?

    init(project: String, screenshot: String?) throws {
        let source = try String(contentsOfFile: project + "/src/helper.mjs", encoding: .utf8)
        let start = source.range(of: "const sharedCSS = `")!.upperBound
        let end = source.range(of: "\n`;", range: start..<source.endIndex)!.lowerBound
        css = String(source[start..<end])
        precondition(!css.contains("${"), "Fixture expects a literal shared stylesheet")
        self.screenshot = screenshot
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 820, height: 440), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func start() {
        webView.loadHTMLString("""
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
          html { --codex-composer-alpha:.70; --codex-composer-blur:7px; }
          body { margin:0; font:18px system-ui; color:white;
            background:linear-gradient(120deg,#135f68,#1c203d); }
          #root { padding:40px; }
          aside.app-shell-left-panel::after { content:''; background:inherit; pointer-events:none; }
          ._ComposerLayoutRoot_fixture { position:relative; display:flex; flex-direction:column;
            --composer-layout-surface-background:rgb(50,50,50);
            --composer-layout-surface-backdrop-filter:none; }
          ._ComposerLayoutRoot_fixture:not([data-composer-utility-bar-variant=home]),
          [data-composer-utility-bar-variant=home] ._ComposerLayoutBody_fixture {
            background-color:var(--composer-layout-surface-background);
            -webkit-backdrop-filter:var(--composer-layout-surface-backdrop-filter);
            backdrop-filter:var(--composer-layout-surface-backdrop-filter);
            border-radius:28px;
          }
          .utility { height:44px; margin:0 18px -7px; padding:12px 20px;
            border-radius:24px 24px 0 0; background:#252525; box-sizing:border-box; }
          ._ComposerLayoutBody_fixture { height:150px; position:relative; padding:20px; box-sizing:border-box; }
          button { position:absolute; right:16px; bottom:16px; border:0; border-radius:20px; padding:8px 18px; }
        </style>
        <div id="codex-live-background"><div style="position:absolute;inset:0;background:linear-gradient(120deg,#135f68,#1c203d)"></div></div>
        <div id="root"><aside class="app-shell-left-panel"></aside>
          <section id="composer" class="_ComposerLayoutRoot_fixture" data-composer-utility-bar-variant="home">
            <header class="utility">Project · This computer</header>
            <div class="_ComposerLayoutBody_fixture"><div contenteditable="true">Type a message</div><button>Send</button></div>
          </section>
        </div>
        """, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        do {
            let payload = String(data: try JSONSerialization.data(withJSONObject: ["css": css]), encoding: .utf8)!
            let script = """
            (() => {
              try {
              const assert = (ok, message) => { if (!ok) throw Error(message); };
              const geometry = () => [...document.querySelectorAll('#composer, .utility, ._ComposerLayoutBody_fixture, button')]
                .map(node => { const r=node.getBoundingClientRect(); return [r.x,r.y,r.width,r.height]; });
              const before = JSON.stringify(geometry());
              const style = document.createElement('style');
              style.textContent = (\(payload)).css;
              document.head.append(style);
              const reference = document.createElement('i'); document.body.append(reference);
              const expectedColor = amount => {
                reference.style.backgroundColor = `rgba(11,17,34,${amount})`;
                return getComputedStyle(reference).backgroundColor;
              };
              const filter = node => getComputedStyle(node).getPropertyValue('backdrop-filter') ||
                getComputedStyle(node).getPropertyValue('-webkit-backdrop-filter');
              for (const home of [true,false,true]) {
                const composer = document.getElementById('composer');
                if (home) composer.dataset.composerUtilityBarVariant='home';
                else composer.removeAttribute('data-composer-utility-bar-variant');
                for (const amount of [.84,.47]) {
                  document.documentElement.style.setProperty('--codex-composer-alpha', amount);
                  for (const blur of ['7px','0px']) {
                    document.documentElement.style.setProperty('--codex-composer-blur', blur);
                    const surface = home ? composer.querySelector('._ComposerLayoutBody_fixture') : composer;
                    if (home) {
                      assert(getComputedStyle(composer).backgroundColor === 'rgba(0, 0, 0, 0)', 'Home wrapper paints a rectangular background');
                      assert(filter(composer) === 'none', 'Home wrapper must not paint a second blur layer');
                    }
                    assert(getComputedStyle(surface).backgroundColor === expectedColor(amount), 'Rounded surface must follow composer transparency');
                    assert(filter(surface).includes(`blur(${blur})`), 'Blur belongs on the actual surface');
                    assert(getComputedStyle(surface).borderTopLeftRadius === '28px', 'Native rounded corners must remain unchanged');
                    assert(JSON.stringify(geometry()) === before, 'Surface styles must not change geometry or control positions');
                  }
                }
              }
              const old = document.getElementById('composer'); old.replaceWith(old.cloneNode(true));
              const fresh = document.getElementById('composer');
              assert(getComputedStyle(fresh).backgroundColor === 'rgba(0, 0, 0, 0)', 'Newly created home composers must stay clear');
              assert(getComputedStyle(fresh.querySelector('._ComposerLayoutBody_fixture')).backgroundColor === expectedColor(.47), 'New composers must inherit surface styling without reapplying');
              const sidebar = getComputedStyle(document.querySelector('aside'), '::after');
              assert(sidebar.backgroundColor === 'rgba(0, 0, 0, 0)' && sidebar.pointerEvents === 'none', 'Sidebar decoration regression');
              reference.remove();
              return {passed:true,homeAndThread:true,routeChanges:true,freshComposer:true,geometryUnchanged:true,sidebarPreserved:true};
              } catch (error) { return {passed:false,error:String(error.message || error)}; }
            })()
            """
            webView.evaluateJavaScript(script) { result, error in
                if let error { self.fail(error.localizedDescription); return }
                guard let value = result, let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else {
                    self.fail("Missing fixture result"); return
                }
                print(String(data: data, encoding: .utf8)!)
                guard (value as? [String: Any])?["passed"] as? Bool == true else {
                    self.fail((value as? [String: Any])?["error"] as? String ?? "Fixture assertions failed"); return
                }
                guard let screenshot = self.screenshot else { exit(0) }
                self.webView.takeSnapshot(with: nil) { image, error in
                    guard let tiff = image?.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:]) else {
                        self.fail(error?.localizedDescription ?? "Snapshot unavailable"); return
                    }
                    do { try png.write(to: URL(fileURLWithPath: screenshot)); exit(0) }
                    catch { self.fail(error.localizedDescription) }
                }
            }
        } catch { fail(error.localizedDescription) }
    }

    func fail(_ message: String) { fputs("FAIL: \(message)\n", stderr); exit(1) }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
do {
    let args = CommandLine.arguments
    let probe = try ComposerSurfaceProbe(project: args.count > 1 ? args[1] : FileManager.default.currentDirectoryPath,
                                         screenshot: args.count > 2 ? args[2] : nil)
    probe.start()
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) { probe.fail("WebKit fixture timed out") }
    application.run()
    withExtendedLifetime(probe) {}
} catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
