# Popup Overlay: design

Date: 2026-10-05
Status: waiting for review

## Goal

A single web page that shows one centred confirmation dialog on a dimmed,
see-through backdrop. The iOS app loads the page in a full-screen, transparent
`WKWebView` placed on top of a native screen, so the native screen stays visible
(darkened) around the dialog.

The user closes the popup by tapping OK, tapping Cancel, or tapping outside the
dialog. Each of these asks the app to close the web view through the existing
`closeWebviewWithResult` JS bridge.

## Decisions

| Topic | Decision |
|---|---|
| Purpose | One specific popup with fixed content (not a reusable template) |
| Content | Short confirmation: optional icon, title, one to three lines of text, two buttons |
| Backdrop | Dimmed: 40% black, drawn by the web page |
| OK button | Calls the bridge with `result: "ok"` |
| Cancel button | Calls the bridge with `result: "cancel"` |
| Tap outside | Calls the bridge with `result: "cancel"` |
| Bridge | Existing `closeWebviewWithResult`, flat payload `{ name, result }` |
| Stack | One static `index.html`, inline CSS and JS, no build step, no dependencies |

Not decided yet, so the build uses placeholders that are easy to change:

- **Text:** English placeholders (title, message, `Cancel`, `OK`), kept together
  in one block of the HTML.
- **Brand colour:** blue `#185FA5`, kept in one CSS variable `--accent`.

## Assumptions

- The host app already handles `closeWebviewWithResult` on the `observer`
  message handler: it closes the web view and passes `result` to the caller.
  This matches the existing mini-app web demo, which sends the same payload.
- The host app can be changed to make the web view transparent (see "Native
  host requirements"). Without those settings the area outside the dialog is
  white, whatever the CSS says.
- Minimum iOS version is 13 or later.

## Files

| File | Purpose |
|---|---|
| `index.html` | The popup: markup, styles and script in one file |
| `ios/PopupOverlayViewController.swift` | Example host showing the required `WKWebView` settings and the message handling |
| `README.md` | Bridge contract, how to change text and colour, how to test |

## Layout

Sizes are at the default iOS text size.

- **Page:** `html` and `body` have a transparent background and fill the
  screen. Nothing scrolls.
- **Backdrop:** fixed to all four edges, `rgba(0, 0, 0, 0.4)`. It also covers
  the status bar and home indicator areas (`viewport-fit=cover`).
- **Card:** centred horizontally and vertically inside the safe area. Width is
  the screen width minus 24px on each side, up to 327px. Corner radius 20px.
  Padding 24px top, 20px sides and bottom. Shadow `0 12px 40px rgba(0,0,0,0.18)`.
- **Icon (optional):** 48px circle in a light tint of the accent colour, with a
  simple inline SVG question mark. Removing the element removes the icon.
- **Title:** 18px, semibold, centred.
- **Message:** 15px, line height 1.5, secondary colour, centred, 8px below the
  title.
- **Buttons:** 20px below the message, side by side, equal width, 12px apart,
  48px high, 12px corner radius, 16px semibold label. Cancel is on the left
  with a neutral grey fill. OK is on the right with the accent fill and white
  text. If a label does not fit on one line, the buttons stack with OK on top.

### Colours

| Token | Light | Dark |
|---|---|---|
| Card | `#FFFFFF` | `#2A2B2F` |
| Title | `#1A1A1A` | `#FFFFFF` |
| Message | `#5F6368` | `#B4B6BB` |
| Cancel fill / label | `#EEEFF1` / `#1A1A1A` | `#3A3B40` / `#FFFFFF` |
| OK fill / label | `--accent` / `#FFFFFF` | `--accent` / `#FFFFFF` |
| Backdrop | `rgba(0,0,0,0.4)` | `rgba(0,0,0,0.4)` |

Dark mode follows the system setting through `prefers-color-scheme`.

## Behaviour

- **Entrance:** the backdrop fades in and the card fades in while scaling from
  0.94 to 1, over about 200ms. With Reduce Motion on, only the fade plays.
- **Closing:** OK, Cancel and a tap on the backdrop each call
  `closeWebviewWithResult` once, immediately, then play a 150ms fade-out.
  A tap counts as "outside" only when it lands on the backdrop itself, not on
  the card.
- **Lock:** after the first close, the buttons and the backdrop stop
  responding, so a double tap cannot send two messages.
- **Escape key:** sends `cancel`, for hardware keyboards and browser testing.
- **Native feel:** no scrolling, rubber-band bounce, pinch zoom, double-tap
  zoom, text selection, long-press callout or grey tap highlight. Buttons show
  a pressed state.
- **Text size:** text uses the iOS system font and follows the user's text
  size setting. If large text makes the card taller than the screen, the
  message area scrolls inside the card and the buttons stay visible.
- **Accessibility:** the card is `role="alertdialog"` with `aria-modal="true"`,
  labelled by the title and described by the message. Focus moves to the card
  when the page loads. Buttons are real `<button>` elements at least 44px high.

## Bridge contract

One message, sent from the web page to the app. Nothing is sent back.

```js
function closeWebviewWithResult(result) {
  var obj = { name: 'closeWebviewWithResult', result: result };

  if (!window.bridge) {
    window.bridge = {};
  }

  if (window.JSBridge) {
    // Android: one JSON-string argument
    window.JSBridge.closeWebviewWithResult(JSON.stringify(obj));
  } else if (window.webkit) {
    // iOS
    window.webkit.messageHandlers.observer.postMessage(obj);
  }
}
```

| User action | `result` |
|---|---|
| Tap OK | `"ok"` |
| Tap Cancel | `"cancel"` |
| Tap outside the card | `"cancel"` |
| Press Escape | `"cancel"` |

The built version follows this order (Android first, then iOS) and adds two
safety checks that do not change behaviour inside the app:

- It checks that the Android method and the iOS `observer` handler exist before
  calling them, so a missing bridge cannot throw an error.
- When no bridge is found (a desktop browser), it logs the payload to the
  console so the page can be tested outside the app.

The script avoids syntax newer than iOS 13 supports (for example `?.`), and the
CSS avoids `inset`, flexbox `gap` and `dvh` for the same reason.

## Native host requirements

`ios/PopupOverlayViewController.swift` is an example, not a replacement for the
app's existing web view. It shows the settings the real host needs:

- **Transparent web view:** `isOpaque = false`, `backgroundColor = .clear`,
  `scrollView.backgroundColor = .clear`, and on iOS 15 and later
  `underPageBackgroundColor = .clear`. These are set before the page loads.
- **No scrolling:** `scrollView.isScrollEnabled = false`,
  `scrollView.bounces = false`,
  `scrollView.contentInsetAdjustmentBehavior = .never`. The web view is pinned
  to the edges of the screen, not to the safe area.
- **Presentation:** the view controller uses `.overFullScreen` so the screen
  behind stays in place, with a clear view background. It is presented without
  animation because the page animates itself in, and dismissed with a
  cross-dissolve.
- **Message handling:** registers `observer`, reads `name` and `result` from
  the message body, and on `closeWebviewWithResult` dismisses and returns
  `result` to the caller.
- **Load failure:** if the page fails to load, the host dismisses and returns
  `"cancel"`. Otherwise an invisible full-screen web view would block the app.
- **Loading:** shows both options, a bundled file (`loadFileURL`) and a remote
  URL.

## Error handling

| Case | Result |
|---|---|
| No bridge (desktop browser) | Payload is logged to the console; the popup fades out |
| Double tap | Only the first tap sends a message |
| Page fails to load in the app | Host dismisses and returns `"cancel"` |
| Long text or very large text size | Message scrolls inside the card; buttons wrap to two rows if needed |

## Testing

- **In a browser (done as part of the build):** at a phone-sized viewport,
  check the layout in light and dark mode, and check that OK, Cancel, tap
  outside and Escape each send exactly one message with the right `result`,
  using a mock `observer` handler. Check that a second tap sends nothing.
- **In the iOS app (needs you):** the build cannot run inside your app. The
  README lists what to check on a simulator or device: the native screen is
  visible and dimmed around the card, there is no white flash, nothing scrolls
  or bounces, and each close path returns the right result to the app.

## Out of scope

- Passing text or options from the app into the page.
- Android host code. The Android bridge call is included; an Android example
  host is not.
- Translations beyond editing the text block in `index.html`.
