import UIKit
import WebKit

/// Example host for the popup overlay page.
///
/// Shows a transparent, full-screen web view on top of the current screen, loads the
/// popup page, and returns the result the page sends through `closeWebviewWithResult`.
///
///     let url = URL(string: "https://misternay.github.io/popup-overlay/")!
///     let popup = PopupOverlayViewController(source: .remote(url)) { result in
///         print(result) // "ok" or "cancel"
///     }
///     present(popup, animated: false) // the page animates itself in
public final class PopupOverlayViewController: UIViewController {

    public enum Source {
        /// A page hosted on a server.
        case remote(URL)
        /// A copy of `index.html` inside the app. `readAccess` is the folder that contains it.
        case bundled(fileURL: URL, readAccess: URL)
    }

    private static let messageHandlerName = "observer"
    private static let closeCommand = "closeWebviewWithResult"
    private static let cancelResult = "cancel"

    private let source: Source
    private var onResult: ((String) -> Void)?
    private var webView: WKWebView?

    public init(source: Source, onResult: @escaping (String) -> Void) {
        self.source = source
        self.onResult = onResult
        super.init(nibName: nil, bundle: nil)
        // Keep the presenting screen in place behind the web view.
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        // VoiceOver should not read the screen behind the popup.
        view.accessibilityViewIsModal = true

        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(WeakScriptMessageHandler(self), name: Self.messageHandlerName)

        let webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.navigationDelegate = self

        // Transparency. Without these the area outside the card is white.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        if #available(iOS 15.0, *) {
            webView.underPageBackgroundColor = .clear
        }

        // The page never scrolls. Stop the rubber-band bounce and the safe-area insets.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Pin to the screen edges, not the safe area, so the dim covers the whole screen.
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        self.webView = webView

        switch source {
        case .remote(let url):
            webView.load(URLRequest(url: url))
        case .bundled(let fileURL, let readAccess):
            webView.loadFileURL(fileURL, allowingReadAccessTo: readAccess)
        }
    }

    /// Closes the popup and reports the result once. Later calls do nothing.
    private func finish(with result: String) {
        guard let onResult = onResult else { return }
        self.onResult = nil
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)

        guard presentingViewController != nil else {
            onResult(result)
            return
        }
        dismiss(animated: true) {
            onResult(result)
        }
    }
}

// MARK: - Messages from the page

extension PopupOverlayViewController: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName,
              let body = message.body as? [String: Any],
              body["name"] as? String == Self.closeCommand else { return }
        finish(with: body["result"] as? String ?? Self.cancelResult)
    }
}

// MARK: - Load failures

// If the page cannot be shown, close. Otherwise an invisible web view would block the app.
extension PopupOverlayViewController: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode >= 400 {
            decisionHandler(.cancel)
            finish(with: Self.cancelResult)
            return
        }
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(with: Self.cancelResult)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(with: Self.cancelResult)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(with: Self.cancelResult)
    }
}

// MARK: - Weak message handler

/// `WKUserContentController` keeps its handler alive. This wrapper avoids a retain cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
