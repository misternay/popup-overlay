# Popup Overlay

A single web page that shows a centred confirmation dialog on a dimmed, see-through
backdrop. It is made to be loaded in a transparent, full-screen `WKWebView` on top of
a native iOS screen, so the native screen stays visible around the dialog.

Live page: https://misternay.github.io/popup-overlay/

## How it works

- The page background is transparent. Only the dim layer and the card are drawn.
- OK, Cancel, a tap outside the card and the Escape key each close the popup.
- Closing calls the native JS bridge once. The app then closes the web view.

## Bridge contract

The page sends one message and expects nothing back.

| User action | `result` |
|---|---|
| Tap OK | `"ok"` |
| Tap Cancel | `"cancel"` |
| Tap outside the card | `"cancel"` |
| Press Escape | `"cancel"` |

On iOS the page posts an object to the `observer` message handler:

```js
window.webkit.messageHandlers.observer.postMessage({
  name: 'closeWebviewWithResult',
  result: 'ok'
});
```

On Android it passes the same payload as one JSON string:

```js
window.JSBridge.closeWebviewWithResult('{"name":"closeWebviewWithResult","result":"ok"}');
```

If `window.JSBridge` exists the page uses Android and skips iOS. With no bridge, for
example in a desktop browser, it logs the payload to the console.

## Change the text and colour

Everything is in `index.html`:

- **Text:** edit the title, message and button labels in the block marked
  `<!-- Text: ... -->`.
- **Icon:** delete the block marked `<!-- Optional icon: ... -->` to remove it.
- **Colour:** change `--accent` at the top of the `<style>` block.
- **Result values:** change `RESULT_OK` and `RESULT_CANCEL` at the top of the script.

## iOS host

The area outside the card is only see-through when the web view itself is transparent.
`ios/PopupOverlayViewController.swift` is a working example. These settings matter:

```swift
webView.isOpaque = false
webView.backgroundColor = .clear
webView.scrollView.backgroundColor = .clear
webView.scrollView.isScrollEnabled = false
webView.scrollView.bounces = false
webView.scrollView.contentInsetAdjustmentBehavior = .never
```

Also:

- Present the view controller with `.overFullScreen`, so the screen behind stays visible.
- Pin the web view to the screen edges, not to the safe area.
- If the page fails to load, close the web view. Otherwise an invisible view blocks the app.

Using the example:

```swift
let url = URL(string: "https://misternay.github.io/popup-overlay/")!
let popup = PopupOverlayViewController(source: .remote(url)) { result in
    print(result) // "ok" or "cancel"
}
present(popup, animated: false) // the page animates itself in
```

To load a copy bundled in the app instead, add `index.html` to the app target and use:

```swift
let file = Bundle.main.url(forResource: "index", withExtension: "html")!
let popup = PopupOverlayViewController(
    source: .bundled(fileURL: file, readAccess: file.deletingLastPathComponent())
) { result in
    print(result)
}
```

## Test

Run the browser tests from the repository root. This needs `python3` and Google Chrome:

```bash
bash tests/run.sh
```

Expected output: `RESULT: PASS 21/21`.

You can also open the test page in any browser:
https://misternay.github.io/popup-overlay/tests/popup.test.html

The tests cannot check the real app. On a simulator or a device, check that:

- the native screen is visible and dimmed around the card, including under the status
  bar and the home indicator
- there is no white flash when the popup opens
- nothing scrolls, bounces or zooms
- OK returns `"ok"`, and Cancel and a tap outside return `"cancel"`
- the card looks right in dark mode and at the largest text size

## Requirements

iOS 13 or later. No build step and no dependencies.
